import { Injectable } from '@nestjs/common';

export interface Product {
  sku: string;
  name: string;
  category: string;
  unitPrice: number;
  stock: number;
  reorderLevel: number;
}

// Placeholder data. Replace the store behind this service with the real
// pharmacy system (database, POS or API) when it is available.
const SEED: Product[] = [
  { sku: 'PARA-500-24', name: 'Paracetamol 500mg x24', category: 'analgesic', unitPrice: 3.5, stock: 120, reorderLevel: 40 },
  { sku: 'IBU-200-16', name: 'Ibuprofen 200mg x16', category: 'analgesic', unitPrice: 4.2, stock: 18, reorderLevel: 30 },
  { sku: 'CET-10-30', name: 'Cetirizine 10mg x30', category: 'antihistamine', unitPrice: 6.9, stock: 65, reorderLevel: 20 },
  { sku: 'VITC-1000-60', name: 'Vitamin C 1000mg x60', category: 'supplement', unitPrice: 11.0, stock: 8, reorderLevel: 15 },
];

@Injectable()
export class InventoryService {
  private readonly products: Product[] = SEED.map((p) => ({ ...p }));

  search(query: string, limit = 10): Product[] {
    const q = query.trim().toLowerCase();
    return this.products
      .filter(
        (p) =>
          p.name.toLowerCase().includes(q) ||
          p.sku.toLowerCase().includes(q) ||
          p.category.toLowerCase().includes(q),
      )
      .slice(0, limit);
  }

  findBySku(sku: string): Product | undefined {
    const wanted = sku.trim().toLowerCase();
    return this.products.find((p) => p.sku.toLowerCase() === wanted);
  }

  lowStock(): Product[] {
    return this.products.filter((p) => p.stock <= p.reorderLevel);
  }
}
