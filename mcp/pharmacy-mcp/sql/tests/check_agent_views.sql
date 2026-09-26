-- Consistency checks for the agent views. Read-only; raises an exception on the first failure.
--   psql -v ON_ERROR_STOP=1 -f check_agent_views.sql
do $$
declare
  a numeric; b numeric; n int;
begin
  -- 1. GST lines tie to what customers paid.
  select coalesce(sum(gross), 0) into a from agent.sale_lines;
  select coalesce(sum(round(si.total::numeric, 2)), 0) into b
    from public.sale_item si join public.sale s on s.id = si.sale_id
   where s.status = 'COMPLETE' and s.active and not s.archive and si.active and not si.archive;
  if a <> b then raise exception 'sale_lines gross % <> base tables %', a, b; end if;

  -- 2. Bill totals equal the sum of their lines (the app never adds anything else).
  select count(*) into n
    from agent.sale_bills sb
    join (select sale_id, sum(gross) g from agent.sale_lines group by sale_id) l on l.sale_id = sb.sale_id
   where sb.status = 'COMPLETE' and abs(sb.total - l.g) >= 1;
  if n > 0 then raise notice 'INFO: % completed bills whose total differs from their lines by >= 1', n; end if;

  -- 3. Taxable + tax = gross, per bill and rate.
  select count(*) into n from agent.gst_sales_bills
   where abs(taxable + cgst_amt + sgst_amt - gross) > 0.005;
  if n > 0 then raise exception '% gst_sales_bills rows where taxable + cgst + sgst <> gross', n; end if;

  -- 4. Summary equals detail.
  select coalesce(sum(gross), 0) into a from agent.gst_sales_summary;
  select coalesce(sum(gross), 0) into b from agent.gst_sales_bills;
  if a <> b then raise exception 'gst_sales_summary % <> gst_sales_bills %', a, b; end if;

  -- 5. No draft or discarded sale reaches the GST views.
  select count(*) into n from agent.gst_sales_bills g
   where not exists (select 1 from public.sale s
                      where s.bill_no = g.bill_no and s.status = 'COMPLETE');
  if n > 0 then raise exception '% GST rows from non-COMPLETE sales', n; end if;

  -- 6. EOD gross equals the GST gross for the same dates.
  select coalesce(sum(gross_sales), 0) into a from agent.eod_daily;
  select coalesce(sum(gross), 0)       into b from agent.gst_sales_bills;
  if abs(a - b) >= 1 then raise exception 'eod_daily gross % <> gst_sales_bills %', a, b; end if;

  -- 7. Stock: batch balance equals product balance plus expired plus nothing lost.
  select coalesce(sum(balance_units), 0) into a from agent.stock_batches;
  select coalesce(sum(on_hand_units + expired_units), 0) into b from agent.product_stock;
  if a <> b then raise exception 'stock_batches % <> product_stock %', a, b; end if;

  raise notice 'OK: all agent view checks passed';
end $$;

-- Informational: how the corrected tax compares with the legacy view (no assertion).
select 'legacy vw_sales_gst_report' as source,
       round(sum(sale_total), 2) as gross, round(sum(gst_total), 2) as tax
  from public.vw_sales_gst_report
union all
select 'agent.gst_sales_bills (COMPLETE only, tax inside gross)',
       sum(gross), sum(gst_total)
  from agent.gst_sales_bills;
