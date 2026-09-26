import { Inject, Injectable } from '@nestjs/common';
import type pg from 'pg';
import { PG_POOL } from '../database/database.module.js';

export interface BillGap {
  bill_no: number;
  status: string | null;
  bill_date: string | null;
}

/**
 * Splits missing bill numbers into ones the system can explain and ones it cannot:
 *   discarded / pending - a sale in that state holds the number
 *   used_elsewhere      - the number belongs to a completed bill dated outside the month
 *   unexplained         - no sale row at all (deleted, or a number that was never used)
 * The four counts always add up to `missing`.
 */
export function summarizeGaps(gaps: BillGap[]) {
  const count = (pick: (g: BillGap) => boolean) => gaps.filter(pick).length;
  const discarded = count((g) => g.status === 'DISCARDED');
  const pending = count((g) => g.status === 'PENDING');
  const unexplained = count((g) => g.status === null);
  return {
    missing: gaps.length,
    explained_discarded: discarded,
    explained_pending: pending,
    used_elsewhere: gaps.length - discarded - pending - unexplained,
    unexplained,
  };
}

/** Every query reads the `agent` schema only. No customer names or phone numbers are selected. */
@Injectable()
export class PharmacyRepository {
  constructor(@Inject(PG_POOL) private readonly pool: pg.Pool) {}

  private async rows<T = Record<string, unknown>>(
    sql: string,
    params: unknown[] = [],
  ): Promise<T[]> {
    return (await this.pool.query(sql, params)).rows as T[];
  }

  async today(): Promise<string> {
    const [r] = await this.rows<{ d: string }>('select agent.today() as d');
    return r.d;
  }

  async eod(date?: string) {
    const day = date ?? (await this.today());
    const [row] = await this.rows(
      'select * from agent.eod_daily where bill_date = $1::date',
      [day],
    );
    const [avg] = await this.rows<{
      days: number;
      avg_gross: number | null;
      avg_bills: number | null;
    }>(
      `select count(*)::int as days, round(avg(gross_sales), 2) as avg_gross, round(avg(bills), 1) as avg_bills
         from agent.eod_daily
        where bill_date < $1::date and bill_date >= $1::date - 7`,
      [day],
    );
    const gross = (row?.gross_sales as number | undefined) ?? 0;
    return {
      date: day,
      day: row ?? null,
      previous_7_days: avg,
      gross_vs_avg_pct:
        avg.avg_gross && avg.avg_gross > 0
          ? Math.round(((gross - avg.avg_gross) / avg.avg_gross) * 1000) / 10
          : null,
    };
  }

  async expiring(days: number, limit: number) {
    const where = `balance_units > 0 and exp_date is not null and exp_date <= agent.today() + $1::int`;
    const [summary] = await this.rows(
      `select count(*)::int as batches,
              coalesce(sum(stock_cost_est), 0) as stock_cost_est,
              count(*) filter (where exp_date < agent.today())::int as already_expired_batches,
              coalesce(sum(stock_cost_est) filter (where exp_date < agent.today()), 0) as already_expired_cost_est
         from agent.stock_batches where ${where}`,
      [days],
    );
    const items = await this.rows(
      `select title, batch, exp_date, days_to_expiry, balance_units, pack, stock_cost_est
         from agent.stock_batches where ${where}
        order by exp_date, title limit $2`,
      [days, limit],
    );
    return { within_days: days, summary, items };
  }

  async lowStock(coverDays: number, limit: number) {
    const where = `units_sold_90d > 0 and days_of_cover < $1`;
    const [{ total }] = await this.rows<{ total: number }>(
      `select count(*)::int as total from agent.product_stock where ${where}`,
      [coverDays],
    );
    const items = await this.rows(
      `select title, on_hand_units, pack, units_sold_90d, days_of_cover, last_sale_date
         from agent.product_stock where ${where}
        order by days_of_cover, title limit $2`,
      [coverDays, limit],
    );
    return { cover_days_below: coverDays, total_matching: total, items };
  }

  async gstMonth(month: string) {
    const first = `${month}-01`;
    const sales = await this.rows(
      `select tax_pcnt, bills, gross, taxable, cgst, sgst, tax
         from agent.gst_sales_summary where month = $1::date order by tax_pcnt`,
      [first],
    );
    const returns = await this.rows(
      `select tax_pcnt, return_lines, taxable, cgst, sgst, tax, gross
         from agent.gst_returns_summary where month = $1::date order by tax_pcnt`,
      [first],
    );
    const [check] = await this.rows(
      `select count(distinct bill_no)::int as bills,
              coalesce(round(sum(gross * tax_pcnt / 100), 2), 0) as legacy_export_tax_estimate
         from agent.sale_lines
        where bill_date >= $1::date and bill_date < ($1::date + interval '1 month')`,
      [first],
    );
    const sum = (rows: Record<string, unknown>[], k: string) =>
      Math.round(rows.reduce((a, r) => a + (r[k] as number), 0) * 100) / 100;
    const salesTax = sum(sales, 'tax');
    const returnsTax = sum(returns, 'tax');
    return {
      month,
      note: 'tax is taken out of the tax-inclusive bill total; legacy_export_tax_estimate is what the old export formula (total x rate) would show',
      bills: check.bills,
      sales_by_rate: sales,
      returns_by_rate: returns,
      totals: {
        sales_gross: sum(sales, 'gross'),
        sales_taxable: sum(sales, 'taxable'),
        sales_tax: salesTax,
        returns_taxable: sum(returns, 'taxable'),
        returns_tax: returnsTax,
        net_tax: Math.round((salesTax - returnsTax) * 100) / 100,
        legacy_export_tax_estimate: check.legacy_export_tax_estimate,
        legacy_minus_correct_sales_tax:
          Math.round(
            ((check.legacy_export_tax_estimate as number) - salesTax) * 100,
          ) / 100,
      },
    };
  }

  async billGaps(month: string, limit: number) {
    const first = `${month}-01`;
    const gaps = await this.rows<BillGap>(
      `with b as (
         select bill_no from agent.sale_bills
          where status = 'COMPLETE' and active and not archive and bill_no is not null
            and bill_date >= $1::date and bill_date < ($1::date + interval '1 month')
       ), r as (select min(bill_no) as lo, max(bill_no) as hi from b)
       select g.n as bill_no, sb.status, sb.bill_date::text as bill_date
         from r, generate_series(r.lo, r.hi) as g(n)
         left join b on b.bill_no = g.n
         left join lateral (
           select status, bill_date from agent.sale_bills x
            where x.bill_no = g.n order by x.sale_id desc limit 1
         ) sb on true
        where b.bill_no is null
        order by g.n`,
      [first],
    );
    const range = await this.rows<{ first_bill_no: number | null; last_bill_no: number | null }>(
      `select min(bill_no) as first_bill_no, max(bill_no) as last_bill_no
         from agent.sale_bills
        where status = 'COMPLETE' and active and not archive
          and bill_date >= $1::date and bill_date < ($1::date + interval '1 month')`,
      [first],
    );
    return {
      month,
      ...range[0],
      ...summarizeGaps(gaps),
      gaps: gaps.slice(0, limit),
    };
  }
}
