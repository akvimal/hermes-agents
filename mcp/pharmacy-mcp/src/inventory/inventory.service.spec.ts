import { InventoryService } from './inventory.service.js';

describe('InventoryService', () => {
  const service = new InventoryService();

  it('searches by name, sku and category, case-insensitively', () => {
    expect(service.search('PARACETAMOL')).toHaveLength(1);
    expect(service.search('cet-10')[0].name).toContain('Cetirizine');
    expect(service.search('analgesic')).toHaveLength(2);
  });

  it('respects the limit', () => {
    expect(service.search('analgesic', 1)).toHaveLength(1);
  });

  it('finds a product by sku', () => {
    expect(service.findBySku('iBu-200-16')?.name).toContain('Ibuprofen');
    expect(service.findBySku('nope')).toBeUndefined();
  });

  it('lists products at or below reorder level', () => {
    const skus = service.lowStock().map((p) => p.sku);
    expect(skus).toEqual(['IBU-200-16', 'VITC-1000-60']);
  });
});
