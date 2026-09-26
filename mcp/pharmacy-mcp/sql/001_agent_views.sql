-- pharmacy-mcp: read-only "agent" schema over the RGP back office database.
--
-- Views only, no tables are created or changed. Idempotent: safe to re-run.
-- Apply as the application owner (the role that owns the back office tables).
--
-- Conventions (taken from the back office app's own logic):
--   * sale/stock quantities are in UNITS; a strip/box holds product.pack units
--   * sale_item.price is per unit and EXCLUDES tax
--   * sale_item.total = price * qty * (1 + tax_pcnt/100), i.e. it INCLUDES tax and is what the
--     customer pays. Taxable value = total / (1 + rate/100); tax = total - taxable
--     (the legacy vw_sales_gst_report instead computes tax as total * rate/100, which over-states it)
--   * a sale counts only when status = 'COMPLETE' and neither the sale nor the line is archived
--   * dates are Asia/Kolkata calendar dates; the database server runs in UTC
--   * amounts are rupees, numeric(12,2)
--
-- Customer names appear ONLY in gst_sales_bills / gst_returns_bills (needed for the CA workbook).
-- The MCP tools exposed to the LLM never select them.

create schema if not exists agent;

create or replace function agent.today() returns date
  language sql stable as $$ select (now() at time zone 'Asia/Kolkata')::date $$;

-- One row per sale (any status), no customer details.
create or replace view agent.sale_bills as
select s.id                          as sale_id,
       s.bill_no,
       s.bill_date::date             as bill_date,
       s.status,
       s.active,
       s.archive,
       s.customer_id,
       round(s.total::numeric, 2)    as total,
       round(coalesce(s.cash_amount, 0)::numeric, 2) as cash_amount,
       round(coalesce(s.digi_amount, 0)::numeric, 2) as digi_amount,
       s.digi_method,
       s.order_type,
       s.delivery_type
from public.sale s;

-- One row per completed sale line.
create or replace view agent.sale_lines as
select s.id                          as sale_id,
       s.bill_no,
       s.bill_date::date             as bill_date,
       si.id                         as sale_item_id,
       si.product_id,
       si.qty,
       si.price,
       coalesce(si.tax_pcnt, 0)::numeric as tax_pcnt,
       round(si.total::numeric, 2)   as gross,
       round((si.total / (1 + coalesce(si.tax_pcnt, 0) / 100))::numeric, 2) as taxable,
       round(si.total::numeric, 2)
         - round((si.total / (1 + coalesce(si.tax_pcnt, 0) / 100))::numeric, 2) as tax
from public.sale_item si
join public.sale s on s.id = si.sale_id
where s.status = 'COMPLETE' and s.active and not s.archive
  and si.active and not si.archive;

-- GST sales, one row per bill and tax rate (layout of the "Sales" sheet sent to the CA).
-- Rounding is done per bill and rate, like the existing export.
create or replace view agent.gst_sales_bills as
with g as (
  select l.bill_no, l.bill_date, l.sale_id, l.tax_pcnt, sum(l.gross) as gross
  from agent.sale_lines l
  group by l.bill_no, l.bill_date, l.sale_id, l.tax_pcnt
), t as (
  select g.*,
         round(g.gross / (1 + g.tax_pcnt / 100), 2) as taxable
  from g
)
select t.bill_no,
       t.bill_date,
       coalesce(c.name, '(no customer)')        as customer,
       t.tax_pcnt,
       t.gross,
       t.taxable,
       t.tax_pcnt / 2                           as cgst_pcnt,
       round((t.gross - t.taxable) / 2, 2)      as cgst_amt,
       t.tax_pcnt / 2                           as sgst_pcnt,
       (t.gross - t.taxable) - round((t.gross - t.taxable) / 2, 2) as sgst_amt,
       t.gross - t.taxable                      as gst_total
from t
join public.sale s on s.id = t.sale_id
left join public.customer c on c.id = s.customer_id;

-- GST sales totals by month and rate.
create or replace view agent.gst_sales_summary as
select date_trunc('month', bill_date)::date as month,
       tax_pcnt,
       count(distinct bill_no)              as bills,
       sum(gross)                           as gross,
       sum(taxable)                         as taxable,
       sum(cgst_amt)                        as cgst,
       sum(sgst_amt)                        as sgst,
       sum(gst_total)                       as tax
from agent.gst_sales_bills
group by 1, 2;

-- GST returns (credit notes), one row per returned line. The month is the RETURN date,
-- because a credit note belongs to the month it is issued; the original bill is shown too.
-- The legacy export keyed returns by the original bill date instead.
create or replace view agent.gst_returns_bills as
select (sri.created_on at time zone 'Asia/Kolkata')::date as return_date,
       s.bill_no,
       s.bill_date::date                    as bill_date,
       coalesce(c.name, '(no customer)')    as customer,
       coalesce(si.tax_pcnt, 0)::numeric    as tax_pcnt,
       sri.qty,
       round((sri.qty * si.price)::numeric, 2) as taxable,
       round((sri.qty * si.price * coalesce(si.tax_pcnt, 0) / 100)::numeric, 2) as tax,
       round((sri.qty * si.price * coalesce(si.tax_pcnt, 0) / 200)::numeric, 2) as cgst_amt,
       round((sri.qty * si.price * coalesce(si.tax_pcnt, 0) / 100)::numeric, 2)
         - round((sri.qty * si.price * coalesce(si.tax_pcnt, 0) / 200)::numeric, 2) as sgst_amt,
       round((sri.qty * si.price * (1 + coalesce(si.tax_pcnt, 0) / 100))::numeric, 2) as gross,
       sri.reason
from public.sale_return_item sri
join public.sale_item si on si.id = sri.sale_item_id
join public.sale s on s.id = si.sale_id
left join public.customer c on c.id = s.customer_id
where sri.active and not sri.archive
  and s.status = 'COMPLETE' and s.active and not s.archive
  and si.active and not si.archive;

create or replace view agent.gst_returns_summary as
select date_trunc('month', return_date)::date as month,
       tax_pcnt,
       count(*)                              as return_lines,
       sum(taxable)                          as taxable,
       sum(cgst_amt)                         as cgst,
       sum(sgst_amt)                         as sgst,
       sum(tax)                              as tax,
       sum(gross)                            as gross
from agent.gst_returns_bills
group by 1, 2;

-- End-of-day figures, one row per date that had completed sales.
create or replace view agent.eod_daily as
with done as (
  select * from agent.sale_bills where status = 'COMPLETE' and active and not archive
), day as (
  select bill_date,
         count(*)                                   as bills,
         sum(total)                                 as gross_sales,
         sum(cash_amount)                           as cash,
         coalesce(sum(digi_amount) filter (where upper(digi_method) = 'UPI'), 0)  as upi,
         coalesce(sum(digi_amount) filter (where upper(digi_method) = 'CARD'), 0) as card,
         coalesce(sum(digi_amount) filter (where digi_method is not null
                                            and upper(digi_method) not in ('UPI', 'CARD')), 0) as other_digital,
         count(*) filter (where abs(cash_amount + digi_amount - total) >= 1) as payment_mismatch_bills,
         count(distinct customer_id)                as customers,
         count(*) filter (where coalesce(delivery_type, 'Counter') <> 'Counter') as delivery_bills,
         min(bill_no)                               as first_bill_no,
         max(bill_no)                               as last_bill_no
  from done group by bill_date
), tax as (
  select bill_date, sum(taxable) as taxable, sum(tax) as tax from agent.sale_lines group by bill_date
), ret as (
  select return_date as bill_date, count(*) as return_lines, sum(gross) as return_value
  from agent.gst_returns_bills group by return_date
), open_bills as (
  select bill_date,
         count(*) filter (where status = 'PENDING')   as pending_bills,
         count(*) filter (where status = 'DISCARDED') as discarded_bills
  from agent.sale_bills where status in ('PENDING', 'DISCARDED') group by bill_date
), first_seen as (
  select customer_id, min(bill_date) as first_date from done where customer_id is not null group by customer_id
), newc as (
  select first_date as bill_date, count(*) as new_customers from first_seen group by first_date
)
select d.bill_date,
       d.bills, d.gross_sales,
       coalesce(t.taxable, 0)  as taxable,
       coalesce(t.tax, 0)      as tax,
       d.cash, d.upi, d.card, d.other_digital,
       d.payment_mismatch_bills,
       d.customers,
       coalesce(n.new_customers, 0)  as new_customers,
       d.delivery_bills,
       d.first_bill_no, d.last_bill_no,
       coalesce(r.return_lines, 0)   as return_lines,
       coalesce(r.return_value, 0)   as return_value,
       coalesce(o.pending_bills, 0)   as pending_bills,
       coalesce(o.discarded_bills, 0) as discarded_bills
from day d
left join tax t using (bill_date)
left join ret r using (bill_date)
left join open_bills o using (bill_date)
left join newc n using (bill_date);

-- Stock per purchase batch, counted the way the back office counts it:
--   balance = (qty + free_qty) * pack - units sold + adjustments
-- Only VERIFIED purchase lines are stock. Values are estimates (per-unit cost = ptr_cost / pack).
create or replace view agent.stock_batches as
select pii.id                         as batch_item_id,
       p.id                           as product_id,
       p.title,
       p.brand,
       p.category,
       coalesce(p.pack, 1)            as pack,
       pii.batch,
       pii.exp_date,
       (pii.exp_date - agent.today())  as days_to_expiry,
       pii.mrp_cost                   as mrp_per_pack,
       pii.sale_price                 as sale_price,
       pii.ptr_cost                   as ptr_per_pack,
       pii.tax_pcnt,
       (pii.qty + coalesce(pii.free_qty, 0)) * coalesce(p.pack, 1)         as purchased_units,
       coalesce(sold.qty, 0)          as sold_units,
       coalesce(adj.qty, 0)           as adjusted_units,
       (pii.qty + coalesce(pii.free_qty, 0)) * coalesce(p.pack, 1)
         - coalesce(sold.qty, 0) + coalesce(adj.qty, 0)                    as balance_units,
       round((((pii.qty + coalesce(pii.free_qty, 0)) * coalesce(p.pack, 1)
         - coalesce(sold.qty, 0) + coalesce(adj.qty, 0))
         * pii.ptr_cost / coalesce(p.pack, 1))::numeric, 2)               as stock_cost_est,
       i.invoice_date                 as purchase_date
from public.purchase_invoice_item pii
join public.purchase_invoice i on i.id = pii.invoice_id and i.active and not i.archive
join public.product p on p.id = pii.product_id and not p.archive
left join lateral (
  select sum(si.qty) as qty from public.sale_item si
  where si.purchase_item_id = pii.id and si.active and not si.archive
) sold on true
left join lateral (
  select sum(pq.qty) as qty from public.product_qtychange pq
  where pq.item_id = pii.id and pq.active and not pq.archive
) adj on true
where pii.status = 'VERIFIED' and pii.active and not pii.archive;

-- Stock and 90-day demand per product.
create or replace view agent.product_stock as
with stock as (
  select product_id,
         max(title)    as title,
         max(brand)    as brand,
         max(category) as category,
         max(pack)     as pack,
         coalesce(sum(balance_units) filter (where exp_date is null or exp_date >= agent.today()), 0) as on_hand_units,
         coalesce(sum(balance_units) filter (where exp_date < agent.today()), 0)                       as expired_units
  from agent.stock_batches group by product_id
), demand as (
  select product_id, sum(qty) as units_sold_90d, max(bill_date) as last_sale_date
  from agent.sale_lines
  where bill_date > agent.today() - 90
  group by product_id
)
select st.product_id, st.title, st.brand, st.category, st.pack,
       st.on_hand_units, st.expired_units,
       coalesce(d.units_sold_90d, 0) as units_sold_90d,
       d.last_sale_date,
       case when coalesce(d.units_sold_90d, 0) = 0 then null
            else round(st.on_hand_units / (d.units_sold_90d / 90.0), 1) end as days_of_cover
from stock st
left join demand d on d.product_id = st.product_id;
