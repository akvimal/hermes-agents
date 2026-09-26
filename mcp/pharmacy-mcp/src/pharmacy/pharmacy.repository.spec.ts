import { summarizeGaps } from './pharmacy.repository.js';

describe('summarizeGaps', () => {
  it('splits gaps into explained and unexplained', () => {
    const s = summarizeGaps([
      { bill_no: 1, status: 'DISCARDED', bill_date: '2026-08-01' },
      { bill_no: 2, status: 'PENDING', bill_date: '2026-08-01' },
      { bill_no: 3, status: null, bill_date: null },
      { bill_no: 4, status: null, bill_date: null },
      { bill_no: 5, status: 'COMPLETE', bill_date: '2026-09-01' },
    ]);
    expect(s).toEqual({
      missing: 5,
      explained_discarded: 1,
      explained_pending: 1,
      used_elsewhere: 1,
      unexplained: 2,
    });
  });

  it('handles no gaps', () => {
    expect(summarizeGaps([]).missing).toBe(0);
  });
});
