import { Module } from '@nestjs/common';
import { PharmacyRepository } from './pharmacy.repository.js';

@Module({
  providers: [PharmacyRepository],
  exports: [PharmacyRepository],
})
export class PharmacyModule {}
