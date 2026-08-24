// lib/services/master_proforma_service.dart

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:gmwf/services/local_storage_service.dart';

/// Service responsible for managing the Universal Master Proforma Medicine Catalog.
/// Strictly uses Generic Formulas only (no commercial brand names allowed).
/// Non-editable fields: code/barcode, name (formula), formula, type, dose.
/// Editable fields at branch level: quantity, price, expiry date.
class MasterProformaService {
  static const String boxName = LocalStorageService.masterProformaBox;

  /// Default Master Seed Catalog using generic medicine formulas ONLY.
  static final List<Map<String, dynamic>> _defaultProformaList = [
    {
      'code': 'MED-PARA-500',
      'name': 'Paracetamol (Panadol)',
      'formula': 'Paracetamol (Panadol)',
      'type': 'Tablet',
      'dose': '500 mg',
      'defaultPrice': 2.50,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-PARA-CAF',
      'name': 'Paracetamol + Caffeine (Panadol Extra)',
      'formula': 'Paracetamol + Caffeine (Panadol Extra)',
      'type': 'Tablet',
      'dose': '500 mg',
      'defaultPrice': 3.50,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-PARA-SYR',
      'name': 'Paracetamol (Panadol)',
      'formula': 'Paracetamol (Panadol)',
      'type': 'Syrup',
      'dose': '15 ml',
      'defaultPrice': 80.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-PARA-INJ-100',
      'name': 'Paracetamol (Panadol)',
      'formula': 'Paracetamol (Panadol)',
      'type': 'Infusion',
      'dose': '100 ml',
      'defaultPrice': 120.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-AMX-250',
      'name': 'Amoxicillin (Amoxil)',
      'formula': 'Amoxicillin (Amoxil)',
      'type': 'Capsule',
      'dose': '250 mg',
      'defaultPrice': 10.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-AMX-500',
      'name': 'Amoxicillin (Amoxil)',
      'formula': 'Amoxicillin (Amoxil)',
      'type': 'Capsule',
      'dose': '500 mg',
      'defaultPrice': 18.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-AMX-SYR',
      'name': 'Amoxicillin (Amoxil)',
      'formula': 'Amoxicillin (Amoxil)',
      'type': 'Syrup',
      'dose': '15 ml',
      'defaultPrice': 110.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-CEF-400',
      'name': 'Cefixime (Cefspan)',
      'formula': 'Cefixime (Cefspan)',
      'type': 'Capsule',
      'dose': '400 mg',
      'defaultPrice': 45.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-CEF-SYR',
      'name': 'Cefixime (Cefspan)',
      'formula': 'Cefixime (Cefspan)',
      'type': 'Syrup',
      'dose': '15 ml',
      'defaultPrice': 220.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-FLG-400',
      'name': 'Metronidazole (Flagyl)',
      'formula': 'Metronidazole (Flagyl)',
      'type': 'Tablet',
      'dose': '400 mg',
      'defaultPrice': 4.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-FLG-SYR',
      'name': 'Metronidazole (Flagyl)',
      'formula': 'Metronidazole (Flagyl)',
      'type': 'Syrup',
      'dose': '15 ml',
      'defaultPrice': 65.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-OMP-20',
      'name': 'Omeprazole (Risek)',
      'formula': 'Omeprazole (Risek)',
      'type': 'Capsule',
      'dose': '20 mg',
      'defaultPrice': 15.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-OMP-40',
      'name': 'Omeprazole (Risek)',
      'formula': 'Omeprazole (Risek)',
      'type': 'Capsule',
      'dose': '40 mg',
      'defaultPrice': 25.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-OMP-IV',
      'name': 'Omeprazole (Risek)',
      'formula': 'Omeprazole (Risek)',
      'type': 'Infusion',
      'dose': '100 ml',
      'defaultPrice': 180.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-AUG-625',
      'name': 'Co-Amoxiclav (Augmentin)',
      'formula': 'Co-Amoxiclav (Augmentin)',
      'type': 'Tablet',
      'dose': '625 mg',
      'defaultPrice': 30.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-AUG-1G',
      'name': 'Co-Amoxiclav (Augmentin)',
      'formula': 'Co-Amoxiclav (Augmentin)',
      'type': 'Tablet',
      'dose': '1 g',
      'defaultPrice': 50.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-AUG-SYR',
      'name': 'Co-Amoxiclav (Augmentin)',
      'formula': 'Co-Amoxiclav (Augmentin)',
      'type': 'Syrup',
      'dose': '15 ml',
      'defaultPrice': 240.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-IBU-200',
      'name': 'Ibuprofen (Brufen)',
      'formula': 'Ibuprofen (Brufen)',
      'type': 'Tablet',
      'dose': '200 mg',
      'defaultPrice': 3.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-IBU-400',
      'name': 'Ibuprofen (Brufen)',
      'formula': 'Ibuprofen (Brufen)',
      'type': 'Tablet',
      'dose': '400 mg',
      'defaultPrice': 5.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-DMH-50',
      'name': 'Dimenhydrinate (Gravinate)',
      'formula': 'Dimenhydrinate (Gravinate)',
      'type': 'Tablet',
      'dose': '50 mg',
      'defaultPrice': 2.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-DMH-SYR',
      'name': 'Dimenhydrinate (Gravinate)',
      'formula': 'Dimenhydrinate (Gravinate)',
      'type': 'Syrup',
      'dose': '15 ml',
      'defaultPrice': 60.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-DMH-INJ',
      'name': 'Dimenhydrinate (Gravinate)',
      'formula': 'Dimenhydrinate (Gravinate)',
      'type': 'Injection',
      'dose': '2 cc',
      'defaultPrice': 35.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-DEX-INJ',
      'name': 'Dexamethasone',
      'formula': 'Dexamethasone',
      'type': 'Injection',
      'dose': '2 cc',
      'defaultPrice': 40.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-OND-INJ',
      'name': 'Ondansetron',
      'formula': 'Ondansetron',
      'type': 'Injection',
      'dose': '2 cc',
      'defaultPrice': 55.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-CEF-1G',
      'name': 'Ceftriaxone',
      'formula': 'Ceftriaxone',
      'type': 'Injection',
      'dose': '2 cc',
      'defaultPrice': 150.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-CEF-500M',
      'name': 'Ceftriaxone',
      'formula': 'Ceftriaxone',
      'type': 'Injection',
      'dose': '2 cc',
      'defaultPrice': 110.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-NS-1000',
      'name': '0.9% NaCl (Normal Saline)',
      'formula': '0.9% NaCl',
      'type': 'Infusion',
      'dose': '1000 ml',
      'defaultPrice': 120.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-DS-1000',
      'name': '5% Dextrose + 0.9% NaCl',
      'formula': '5% Dextrose + 0.9% NaCl',
      'type': 'Infusion',
      'dose': '1000 ml',
      'defaultPrice': 130.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-RL-1000',
      'name': 'Ringer Solution',
      'formula': 'Ringer Solution',
      'type': 'Infusion',
      'dose': '1000 ml',
      'defaultPrice': 135.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-DRIP-SET',
      'name': 'IV Administration Set',
      'formula': 'IV Administration Set',
      'type': 'Drip Set',
      'dose': 'Standard',
      'defaultPrice': 45.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-SYR-3CC',
      'name': 'Disposable Syringe 3cc',
      'formula': 'Syringe',
      'type': 'Syringe',
      'dose': '3cc',
      'defaultPrice': 15.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-SYR-5CC',
      'name': 'Disposable Syringe 5cc',
      'formula': 'Syringe',
      'type': 'Syringe',
      'dose': '5cc',
      'defaultPrice': 18.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-SYR-10CC',
      'name': 'Disposable Syringe 10cc',
      'formula': 'Syringe',
      'type': 'Syringe',
      'dose': '10cc',
      'defaultPrice': 25.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-CAN-18IN',
      'name': 'IV Cannula 18"',
      'formula': 'IV Cannula',
      'type': 'Cannula',
      'dose': '18"',
      'defaultPrice': 60.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-CAN-20IN',
      'name': 'IV Cannula 20"',
      'formula': 'IV Cannula',
      'type': 'Cannula',
      'dose': '20"',
      'defaultPrice': 60.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-CAN-22IN',
      'name': 'IV Cannula 22"',
      'formula': 'IV Cannula',
      'type': 'Cannula',
      'dose': '22"',
      'defaultPrice': 60.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-CAN-24IN',
      'name': 'IV Cannula 24"',
      'formula': 'IV Cannula',
      'type': 'Cannula',
      'dose': '24"',
      'defaultPrice': 65.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-NEB-MSK',
      'name': 'Aerosol / Nebulizer Mask',
      'formula': 'Aerosol Mask',
      'type': 'Nebulization',
      'dose': 'Adult/Pediatric',
      'defaultPrice': 120.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-ATR-NEB',
      'name': 'Ipratropium Bromide',
      'formula': 'Ipratropium Bromide',
      'type': 'Nebulization',
      'dose': '250 mcg',
      'defaultPrice': 30.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-VNT-NEB',
      'name': 'Salbutamol Solution',
      'formula': 'Salbutamol',
      'type': 'Nebulization',
      'dose': '5 mg/ml',
      'defaultPrice': 25.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-SRB-Z',
      'name': 'Multivitamin + Zinc (Surbex-Z)',
      'formula': 'Multivitamin + Zinc (Surbex-Z)',
      'type': 'Tablet',
      'dose': 'Standard',
      'defaultPrice': 12.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-VTD3-1000',
      'name': 'Vitamin D3',
      'formula': 'Vitamin D3',
      'type': 'Tablet',
      'dose': '1000 IU',
      'defaultPrice': 10.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-MVIT-TAB',
      'name': 'Multivitamin',
      'formula': 'Multivitamin',
      'type': 'Tablet',
      'dose': 'Standard',
      'defaultPrice': 8.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-MEF-250',
      'name': 'Mefenamic Acid (Ponstan)',
      'formula': 'Mefenamic Acid (Ponstan)',
      'type': 'Tablet',
      'dose': '250 mg',
      'defaultPrice': 3.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-MEF-500',
      'name': 'Mefenamic Acid (Ponstan)',
      'formula': 'Mefenamic Acid (Ponstan)',
      'type': 'Tablet',
      'dose': '500 mg',
      'defaultPrice': 6.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-ENT-TAB',
      'name': 'Metronidazole (flagyl) + Diloxanide',
      'formula': 'Metronidazole (flagyl) + Diloxanide',
      'type': 'Tablet',
      'dose': '250 mg / 375 mg',
      'defaultPrice': 8.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-DRT-40',
      'name': 'Drotaverine (No-Spa)',
      'formula': 'Drotaverine (No-Spa)',
      'type': 'Tablet',
      'dose': '40 mg',
      'defaultPrice': 5.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-HYO-10',
      'name': 'Hyoscine Butylbromide (Buscopan)',
      'formula': 'Hyoscine Butylbromide (Buscopan)',
      'type': 'Tablet',
      'dose': '10 mg',
      'defaultPrice': 4.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-HYO-INJ',
      'name': 'Hyoscine Butylbromide (Buscopan)',
      'formula': 'Hyoscine Butylbromide (Buscopan)',
      'type': 'Injection',
      'dose': '20 mg',
      'defaultPrice': 40.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-PHE-INJ',
      'name': 'Pheniramine Maleate (Avil)',
      'formula': 'Pheniramine Maleate (Avil)',
      'type': 'Injection',
      'dose': '2 cc',
      'defaultPrice': 30.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-ASP-300',
      'name': 'Aspirin (Disprin)',
      'formula': 'Aspirin (Disprin)',
      'type': 'Tablet',
      'dose': '300 mg',
      'defaultPrice': 2.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-ASP-75',
      'name': 'Aspirin',
      'formula': 'Aspirin',
      'type': 'Tablet',
      'dose': '75 mg',
      'defaultPrice': 3.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-PYO-OINT',
      'name': 'Povidone Iodine 10%',
      'formula': 'Povidone Iodine 10%',
      'type': 'Others',
      'dose': '20 g tube',
      'defaultPrice': 90.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-NDL-24IN',
      'name': 'Needle 24"',
      'formula': 'Needle',
      'type': 'Cannula',
      'dose': '24"',
      'defaultPrice': 10.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-NDL-21IN',
      'name': 'Disposable Needle 21"',
      'formula': 'Needle',
      'type': 'Cannula',
      'dose': '21"',
      'defaultPrice': 8.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-NDL-22IN',
      'name': 'Disposable Needle 22"',
      'formula': 'Needle',
      'type': 'Cannula',
      'dose': '22"',
      'defaultPrice': 8.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-NDL-23IN',
      'name': 'Disposable Needle 23"',
      'formula': 'Needle',
      'type': 'Cannula',
      'dose': '23"',
      'defaultPrice': 8.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-NDL-25IN',
      'name': 'Disposable Needle 25"',
      'formula': 'Needle',
      'type': 'Cannula',
      'dose': '25"',
      'defaultPrice': 8.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-NDL-INS',
      'name': 'Insulin Needle 30"',
      'formula': 'Needle',
      'type': 'Cannula',
      'dose': '30"',
      'defaultPrice': 10.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-NDL-DNT',
      'name': 'Dental Needle 27"',
      'formula': 'Needle',
      'type': 'Cannula',
      'dose': '27"',
      'defaultPrice': 15.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-DIC-INJ',
      'name': 'Diclofenac Sodium',
      'formula': 'Diclofenac Sodium',
      'type': 'Injection',
      'dose': '2 cc',
      'defaultPrice': 30.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-DIC-50',
      'name': 'Diclofenac Sodium',
      'formula': 'Diclofenac Sodium',
      'type': 'Tablet',
      'dose': '50 mg',
      'defaultPrice': 5.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-TRM-INJ',
      'name': 'Tramadol Hydrochloride',
      'formula': 'Tramadol',
      'type': 'Injection',
      'dose': '2 cc',
      'defaultPrice': 45.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-HYD-INJ',
      'name': 'Hydrocortisone Sodium Succinate',
      'formula': 'Hydrocortisone',
      'type': 'Injection',
      'dose': '2 cc',
      'defaultPrice': 65.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-MTC-INJ',
      'name': 'Metoclopramide',
      'formula': 'Metoclopramide',
      'type': 'Injection',
      'dose': '2 cc',
      'defaultPrice': 25.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-CIP-DRP',
      'name': 'Ciprofloxacin',
      'formula': 'Ciprofloxacin',
      'type': 'Infusion',
      'dose': '2 cc',
      'defaultPrice': 140.00,
      'isProformaMaster': true,
    },
    // ── Brufen Syrup ───────────────────────────────────────────────
    {
      'code': 'MED-BRF-SYR',
      'name': 'Ibuprofen',
      'formula': 'Ibuprofen',
      'type': 'Syrup',
      'dose': '15 ml',
      'defaultPrice': 120.00,
      'isProformaMaster': true,
    },
    // ── Metoclopramide (Tablet, Injection, Syrup) ───────────────
    {
      'code': 'MED-METCL-TAB',
      'name': 'Metoclopramide (Metoclone)',
      'formula': 'Metoclopramide (Metoclone)',
      'type': 'Tablet',
      'dose': '10 mg',
      'defaultPrice': 5.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-METCL-INJ',
      'name': 'Metoclopramide (Metoclone)',
      'formula': 'Metoclopramide (Metoclone)',
      'type': 'Injection',
      'dose': '2 cc',
      'defaultPrice': 30.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-METCL-SYR',
      'name': 'Metoclopramide (Metoclone)',
      'formula': 'Metoclopramide (Metoclone)',
      'type': 'Syrup',
      'dose': '15 ml',
      'defaultPrice': 70.00,
      'isProformaMaster': true,
    },
    // ── Additional Requested Proforma Items ──────────────────────────────
    {
      'code': 'MED-CPM-4',
      'name': 'Chlorpheniramine Maleate (CPM)',
      'formula': 'Chlorpheniramine Maleate (CPM)',
      'type': 'Tablet',
      'dose': '4 mg',
      'defaultPrice': 2.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-CPM-SYR',
      'name': 'Chlorpheniramine Maleate (CPM)',
      'formula': 'Chlorpheniramine Maleate (CPM)',
      'type': 'Syrup',
      'dose': '15 ml',
      'defaultPrice': 60.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-FLG-INJ',
      'name': 'Metronidazole (Flagyl)',
      'formula': 'Metronidazole (Flagyl)',
      'type': 'Infusion',
      'dose': '100 ml',
      'defaultPrice': 60.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-FLG-400',
      'name': 'Metronidazole (Flagyl)',
      'formula': 'Metronidazole (Flagyl)',
      'type': 'Tablet',
      'dose': '400 mg',
      'defaultPrice': 10.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-FLG-SYR',
      'name': 'Metronidazole (Flagyl)',
      'formula': 'Metronidazole (Flagyl)',
      'type': 'Syrup',
      'dose': '15 ml',
      'defaultPrice': 70.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-VBC-TAB',
      'name': 'Vitamin B Complex (Polybion)',
      'formula': 'Vitamin B Complex (Polybion)',
      'type': 'Tablet',
      'dose': 'Standard',
      'defaultPrice': 4.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-VBC-SYR',
      'name': 'Vitamin B Complex (Polybion)',
      'formula': 'Vitamin B Complex (Polybion)',
      'type': 'Syrup',
      'dose': '15 ml',
      'defaultPrice': 70.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-FOL-TAB',
      'name': 'Folic Acid',
      'formula': 'Folic Acid',
      'type': 'Tablet',
      'dose': '5 mg',
      'defaultPrice': 3.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-SDM-TAB',
      'name': 'Sodamint',
      'formula': 'Sodamint',
      'type': 'Tablet',
      'dose': 'Standard',
      'defaultPrice': 2.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-DEX-TAB',
      'name': 'Dexamethasone',
      'formula': 'Dexamethasone',
      'type': 'Tablet',
      'dose': '0.5 mg',
      'defaultPrice': 3.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-DRT-INJ',
      'name': 'Drotaverine (No-Spa)',
      'formula': 'Drotaverine (No-Spa)',
      'type': 'Injection',
      'dose': '2 cc',
      'defaultPrice': 45.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-VTC-TAB',
      'name': 'Vitamin C',
      'formula': 'Vitamin C',
      'type': 'Tablet',
      'dose': '500 mg',
      'defaultPrice': 5.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-CAL-TAB',
      'name': 'Calcium',
      'formula': 'Calcium',
      'type': 'Tablet',
      'dose': '500 mg',
      'defaultPrice': 8.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-PCP-5',
      'name': 'Prochlorperazine (Stemetil)',
      'formula': 'Prochlorperazine (Stemetil)',
      'type': 'Tablet',
      'dose': '5 mg',
      'defaultPrice': 5.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-NIM-100',
      'name': 'Nimesulide',
      'formula': 'Nimesulide',
      'type': 'Tablet',
      'dose': '100 mg',
      'defaultPrice': 6.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-SRP-20',
      'name': 'Serratiopeptidase (Danzen DS)',
      'formula': 'Serratiopeptidase (Danzen DS)',
      'type': 'Tablet',
      'dose': '20 mg',
      'defaultPrice': 12.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-DOX-100',
      'name': 'Doxycycline',
      'formula': 'Doxycycline',
      'type': 'Capsule',
      'dose': '100 mg',
      'defaultPrice': 12.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-OTC-250',
      'name': 'Oxytetracycline',
      'formula': 'Oxytetracycline',
      'type': 'Capsule',
      'dose': '250 mg',
      'defaultPrice': 10.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-IND-25',
      'name': 'Indomethacin',
      'formula': 'Indomethacin',
      'type': 'Capsule',
      'dose': '25 mg',
      'defaultPrice': 7.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-ANT-SYR',
      'name': 'Antacid (Mucaine / Digas)',
      'formula': 'Aluminium + Magnesium Hydroxide (Mucaine / Digas)',
      'type': 'Syrup',
      'dose': '15 ml',
      'defaultPrice': 85.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-AMC-SYR',
      'name': 'Ammonium Chloride (Hydryllin)',
      'formula': 'Ammonium Chloride (Hydryllin)',
      'type': 'Syrup',
      'dose': '15 ml',
      'defaultPrice': 75.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-CRM-SYR',
      'name': 'Carminative Mixture (Gripe Water)',
      'formula': 'Carminative Mixture (Gripe Water)',
      'type': 'Syrup',
      'dose': '15 ml',
      'defaultPrice': 65.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-LIN-INJ',
      'name': 'Lincomycin (Lincocin)',
      'formula': 'Lincomycin (Lincocin)',
      'type': 'Injection',
      'dose': '2 cc',
      'defaultPrice': 45.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-CYN-INJ',
      'name': 'Cyanocobalamin (Neurobion)',
      'formula': 'Cyanocobalamin (Neurobion)',
      'type': 'Injection',
      'dose': '2 cc',
      'defaultPrice': 35.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-BTP-STD',
      'name': 'Bandage Tape Plaster',
      'formula': 'Bandage Tape Plaster',
      'type': 'Dressing Item',
      'dose': 'Standard',
      'defaultPrice': 40.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-BND-STD',
      'name': 'Bandages',
      'formula': 'Bandages',
      'type': 'Dressing Item',
      'dose': 'Standard',
      'defaultPrice': 30.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-COT-ROL',
      'name': 'Cotton Roll',
      'formula': 'Cotton Roll',
      'type': 'Dressing Item',
      'dose': 'Standard',
      'defaultPrice': 90.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-SNP-STD',
      'name': 'Adhesive First Aid Bandage (Sunny Plast)',
      'formula': 'Adhesive First Aid Bandage (Sunny Plast)',
      'type': 'Dressing Item',
      'dose': 'Standard',
      'defaultPrice': 5.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-PYD-SOL',
      'name': 'Povidone Iodine Solution (Pyodine)',
      'formula': 'Povidone Iodine Solution (Pyodine)',
      'type': 'Dressing Item',
      'dose': 'Standard',
      'defaultPrice': 110.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-ALC-SWB',
      'name': 'Alcohol Swab',
      'formula': 'Alcohol Swab',
      'type': 'Consumables',
      'dose': 'Standard',
      'defaultPrice': 5.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-NDL-24',
      'name': 'Needle 24"',
      'formula': 'Needle',
      'type': 'Consumables',
      'dose': '24"',
      'defaultPrice': 10.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-NS-100',
      'name': '0.9% NaCl (Normal Saline)',
      'formula': '0.9% NaCl (Normal Saline)',
      'type': 'Infusion',
      'dose': '100 ml',
      'defaultPrice': 60.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-NS-500',
      'name': '0.9% NaCl (Normal Saline)',
      'formula': '0.9% NaCl (Normal Saline)',
      'type': 'Infusion',
      'dose': '500 ml',
      'defaultPrice': 110.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-MEF-1000',
      'name': 'Mefenamic Acid',
      'formula': 'Mefenamic Acid',
      'type': 'Tablet',
      'dose': '1000 mg',
      'defaultPrice': 8.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-CIP-250',
      'name': 'Ciprofloxacin',
      'formula': 'Ciprofloxacin',
      'type': 'Capsule',
      'dose': '250 mg',
      'defaultPrice': 15.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-CIP-500',
      'name': 'Ciprofloxacin',
      'formula': 'Ciprofloxacin',
      'type': 'Capsule',
      'dose': '500 mg',
      'defaultPrice': 25.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-OMP-40',
      'name': 'Omeprazole',
      'formula': 'Omeprazole',
      'type': 'Capsule',
      'dose': '40 mg',
      'defaultPrice': 18.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-RL-500',
      'name': 'Ringer Lactate',
      'formula': 'Ringer Lactate',
      'type': 'Infusion',
      'dose': '500 ml',
      'defaultPrice': 130.00,
      'isProformaMaster': true,
    },
  ];

  /// Initialize and seed Proforma Hive Box if empty or update to generic formulas
  static Future<void> seedDefaultProformaIfEmpty() async {
    try {
      final box = await Hive.openBox(boxName);
      // Re-seed master box with generic formulas
      debugPrint('[MasterProformaService] Seeding default generic formula catalog (${_defaultProformaList.length} items)...');
      await box.clear();
      for (final item in _defaultProformaList) {
        final key = 'proforma:${item['code']}';
        await box.put(key, item);
      }
    } catch (e) {
      debugPrint('[MasterProformaService] Error seeding proforma box: $e');
    }
  }

  /// Get all Master Proforma items from Hive cache (or default fallback)
  static List<Map<String, dynamic>> getAllProformaItems() {
    try {
      if (Hive.isBoxOpen(boxName)) {
        final box = Hive.box(boxName);
        final List<Map<String, dynamic>> result = [];
        final Set<String> existingCodes = {};
        for (final key in box.keys) {
          final raw = box.get(key);
          if (raw is Map) {
            final map = Map<String, dynamic>.from(raw);
            
            final itemCode = (map['code'] as String? ?? '').trim();
            // Filter out duplicate/removed items
            if (itemCode == 'MED-VITC-500' || itemCode == 'MED-CAL-500' || itemCode == 'MED-METCL-CAP' || itemCode == 'MED-IBU-SYR' || itemCode == 'MED-SRP-10' || itemCode == 'MED-PARA-INJ-2ML' || itemCode == 'MED-ENT-TAB') {
              box.delete(key);
              continue;
            }

            // Auto-sanitize all brand names to generic formulas
            final cleanName = cleanBrandToFormula(map['name']?.toString() ?? '');
            final cleanFormula = cleanBrandToFormula(map['formula']?.toString() ?? '');
            if (cleanName.isNotEmpty) map['name'] = cleanName;
            if (cleanFormula.isNotEmpty) map['formula'] = cleanFormula;

            final formulaLower = (map['formula'] as String? ?? '').trim().toLowerCase();
            final nameLower = (map['name'] as String? ?? '').trim().toLowerCase();

            // Auto-sanitize Drip type to Infusion
            if (map['type'] == 'Drip') {
              map['type'] = 'Infusion';
            }

            // Auto-sanitize Paracetamol Infusion to Infusion 100 ml always
            if (formulaLower.contains('paracetamol') && (map['type'] == 'Injection' || map['type'] == 'Drip' || map['type'] == 'Infusion')) {
              map['type'] = 'Infusion';
              map['dose'] = '100 ml';
            }

            // Auto-sanitize Omeprazole Infusion
            if (itemCode == 'MED-OMP-IV') {
              map['type'] = 'Infusion';
              map['dose'] = '100 ml';
            }

            // Auto-sanitize Metronidazole (flagyl) items
            if (itemCode == 'MED-FLG-INJ' || itemCode == 'MED-FLG-400' || itemCode == 'MED-FLG-SYR' || formulaLower.contains('metronidazole') || formulaLower.contains('flagyl') || nameLower.contains('flagyl')) {
              map['name'] = 'Metronidazole (flagyl)';
              map['formula'] = 'Metronidazole (flagyl)';
              final rawType = (map['type'] as String? ?? '').trim().toLowerCase();
              if (itemCode == 'MED-FLG-INJ' || rawType == 'infusion' || rawType == 'drip' || rawType == 'injection') {
                map['type'] = 'Infusion';
                map['dose'] = '100 ml';
              } else if (itemCode == 'MED-FLG-400' || rawType == 'tablet') {
                map['type'] = 'Tablet';
                map['dose'] = '400 mg';
              } else if (itemCode == 'MED-FLG-SYR' || rawType == 'syrup') {
                map['type'] = 'Syrup';
                map['dose'] = '15 ml';
              }
            }

            final type = (map['type'] as String? ?? '').trim().toLowerCase();
            
            // Rule: All syrups are 15 ml always
            if (type == 'syrup') {
              map['dose'] = '15 ml';
            }

            // Rule: All injections are cc (2 cc) instead of mg or ml (except Infusions)
            if (type == 'injection') {
              map['dose'] = '2 cc';
            }

            // Auto-sanitize redundant category words from Injection/Infusion names
            if (type == 'injection' || type == 'infusion' || type == 'drip') {
              var name = (map['name'] as String? ?? '').trim();
              name = name.replaceAll(RegExp(r'\s+(Injection|Infusion|\/\s*Infusion|IV)$', caseSensitive: false), '').trim();
              if (name.isNotEmpty) {
                map['name'] = name;
              }
            }

            result.add(map);
            if (map['code'] != null) {
              existingCodes.add(map['code'].toString());
            }
          }
        }

        // Merge any missing default catalog items (e.g. Needles, Paracetamol Inj)
        for (final defItem in _defaultProformaList) {
          final code = defItem['code']?.toString();
          if (code != null && !existingCodes.contains(code)) {
            result.add(Map<String, dynamic>.from(defItem));
            box.put('proforma:$code', defItem);
          }
        }

        if (result.isNotEmpty) {
          result.sort((a, b) => (a['formula'] as String? ?? a['name'] as String? ?? '')
              .compareTo(b['formula'] as String? ?? b['name'] as String? ?? ''));
          return result;
        }
      }
    } catch (e) {
      debugPrint('[MasterProformaService] Error reading proforma items: $e');
    }

    // Fallback to default in-memory list
    return List<Map<String, dynamic>>.from(_defaultProformaList);
  }

  /// Returns all items from proforma master catalog
  static List<Map<String, dynamic>> getAllItems() => getAllProformaItems();

  /// Helper to check if a medicine formula + type is an exact match in Proforma catalog
  static Map<String, dynamic>? findExactMatch(String formulaOrName, String type) {
    final cleanInput = formulaOrName.trim().toLowerCase();
    final cleanType = type.trim().toLowerCase();

    final all = getAllProformaItems();
    for (final item in all) {
      final itemFormula = (item['formula'] as String? ?? '').trim().toLowerCase();
      final itemName = (item['name'] as String? ?? '').trim().toLowerCase();
      final itemType = (item['type'] as String? ?? '').trim().toLowerCase();
      if ((itemFormula == cleanInput || itemName == cleanInput) && itemType == cleanType) {
        return item;
      }
    }
    return null;
  }

  /// Helper to check if a barcode/code already exists in Proforma catalog
  static Map<String, dynamic>? findExactBarcodeMatch(String code) {
    final cleanCode = code.trim().toLowerCase();
    if (cleanCode.isEmpty) return null;

    final all = getAllProformaItems();
    for (final item in all) {
      final itemCode = (item['code'] as String? ?? item['barcode'] as String? ?? '').trim().toLowerCase();
      if (itemCode.isNotEmpty && itemCode == cleanCode) {
        return item;
      }
    }
    return null;
  }

  /// Helper to check if a Name + Dose + Type exact match exists in Proforma catalog
  static Map<String, dynamic>? findExactNameDoseTypeMatch(String name, String type, String dose) {
    final cleanN = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final cleanT = type.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final cleanD = dose.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (cleanN.isEmpty) return null;

    final all = getAllProformaItems();
    for (final item in all) {
      final itemFormula = (item['formula'] as String? ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final itemName = (item['name'] as String? ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final itemType = (item['type'] as String? ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
      final itemDose = (item['dose'] as String? ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

      final matchesName = (itemName == cleanN || itemFormula == cleanN);
      final matchesType = (itemType == cleanT);
      final matchesDose = cleanD.isEmpty || itemDose == cleanD || itemDose == 'standard';
      if (matchesName && matchesType && matchesDose) {
        return item;
      }
    }
    return null;
  }

  /// Checks whether a given user/role has permission to add Proforma catalog items (Register Medicine).
  /// Strictly allowed: Chairman, HQ Manager / Admin / Supervisor.
  /// Strictly blocked: Doctor, Dispenser, Hybrid, Receptionist.
  static bool canManageProformaCatalog({String? role, Map<String, dynamic>? userData}) {
    String r = (role ?? '').trim().toLowerCase();
    if (r.isEmpty && userData != null) {
      r = (userData['role'] ?? userData['userRole'] ?? '').toString().trim().toLowerCase();
    }
    if (r.isEmpty) {
      try {
        if (Hive.isBoxOpen('app_settings')) {
          final uData = Hive.box('app_settings').get('user_data') ?? Hive.box('app_settings').get('currentUser');
          if (uData is Map) {
            r = (uData['role'] ?? uData['userRole'] ?? '').toString().trim().toLowerCase();
          }
        }
      } catch (_) {}
    }

    // Explicitly reject Doctor, Dispenser, Hybrid, and Receptionist
    if (r.contains('doctor') || r.contains('dispens') || r.contains('hybrid') || r.contains('reception')) {
      return false;
    }

    // Allow Chairman, HQ Manager, Admin, Supervisor, President
    if (r.contains('chairman') ||
        r.contains('president') ||
        r.contains('hqmanager') ||
        r.contains('hq_manager') ||
        r.contains('hq manager') ||
        r.contains('manager') ||
        r.contains('admin') ||
        r.contains('supervisor')) {
      return true;
    }

    return false;
  }

  /// Checks whether a given user/role has permission to EDIT or DELETE Master Proforma catalog items.
  /// Strictly allowed: Chairman, HQ Manager, Admin.
  /// Strictly blocked: Doctor, Dispenser, Hybrid, Receptionist.
  static bool canEditOrDeleteProforma({String? role, Map<String, dynamic>? userData}) {
    return canManageProformaCatalog(role: role, userData: userData);
  }

  /// Deletes a proforma catalog item with mandatory audit log reason.
  static Future<bool> deleteProformaItem({
    required String code,
    required Map<String, dynamic> auditLog,
  }) async {
    try {
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox(boxName);
      }
      final box = Hive.box(boxName);
      dynamic existing = box.get('proforma:$code');

      final itemName = (existing is Map)
          ? (existing['name'] ?? existing['formula'] ?? code).toString()
          : code;

      // Delete from Hive proforma box
      await box.delete('proforma:$code');

      // Record audit log entry
      final fullAuditEntry = {
        ...auditLog,
        'action': 'delete_proforma_medicine',
        'medicineCode': code,
        'medicineName': itemName,
        'timestamp': DateTime.now().toIso8601String(),
      };
      await LocalStorageService.saveLocalInventoryLog(fullAuditEntry);

      return true;
    } catch (e) {
      debugPrint('[MasterProformaService] Error deleting proforma item: $e');
      return false;
    }
  }

  /// Adds a new proforma catalog item and records an audit log entry with mandatory reason.
  static Future<bool> saveProformaItem(
    Map<String, dynamic> item, {
    required Map<String, dynamic> auditLog,
  }) async {
    try {
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox(boxName);
      }
      final box = Hive.box(boxName);
      final rawCode = (item['code'] ?? item['barcode'] ?? '').toString().trim();
      final code = rawCode.isNotEmpty ? rawCode : 'MED-GEN-${DateTime.now().millisecondsSinceEpoch}';

      final cleanName = cleanBrandToFormula((item['name'] ?? item['formula'] ?? '').toString());
      final cleanFormula = cleanBrandToFormula((item['formula'] ?? item['name'] ?? '').toString());

      final sanitizedItem = Map<String, dynamic>.from(item);
      sanitizedItem['code'] = code;
      sanitizedItem['name'] = cleanName;
      sanitizedItem['formula'] = cleanFormula;
      sanitizedItem['isProformaMaster'] = true;
      sanitizedItem['updatedAt'] = DateTime.now().toIso8601String();

      // Maintain audit trail list on the item
      final existing = box.get('proforma:$code');
      final List<Map<String, dynamic>> auditTrail = [];
      if (existing is Map && existing['auditTrail'] is List) {
        auditTrail.addAll((existing['auditTrail'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
      }
      auditTrail.add(auditLog);
      sanitizedItem['auditTrail'] = auditTrail;

      await box.put('proforma:$code', LocalStorageService.sanitize(sanitizedItem));

      // Save to local inventory audit logs
      await LocalStorageService.saveLocalInventoryLog({
        ...auditLog,
        'action': auditLog['action'] ?? 'add_proforma_medicine',
        'medicineCode': code,
        'medicineName': cleanName,
        'medicineFormula': cleanFormula,
        'savedAt': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      debugPrint('[MasterProformaService] Error saving proforma item: $e');
      return false;
    }
  }

  /// Edits an existing proforma medicine name/formula with mandatory reason and audit trail.
  static Future<bool> editProformaItemName({
    required String code,
    required String newName,
    required Map<String, dynamic> auditLog,
  }) async {
    try {
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox(boxName);
      }
      final box = Hive.box(boxName);
      dynamic existing = box.get('proforma:$code');

      // Fallback search in default list if not yet customized in Hive
      if (existing == null) {
        for (final defItem in _defaultProformaList) {
          if (defItem['code'] == code) {
            existing = Map<String, dynamic>.from(defItem);
            break;
          }
        }
      }

      if (existing == null) return false;

      final updated = Map<String, dynamic>.from(existing is Map ? existing : {});
      final oldName = (updated['name'] ?? updated['formula'] ?? '').toString();
      final cleanNewName = cleanBrandToFormula(newName);

      updated['name'] = cleanNewName;
      updated['formula'] = cleanNewName;
      updated['updatedAt'] = DateTime.now().toIso8601String();

      // Append to audit trail
      final List<Map<String, dynamic>> auditTrail = [];
      if (updated['auditTrail'] is List) {
        auditTrail.addAll((updated['auditTrail'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
      }
      final fullAuditEntry = {
        ...auditLog,
        'action': 'edit_proforma_medicine_name',
        'medicineCode': code,
        'oldName': oldName,
        'newName': cleanNewName,
        'timestamp': DateTime.now().toIso8601String(),
      };
      auditTrail.add(fullAuditEntry);
      updated['auditTrail'] = auditTrail;

      await box.put('proforma:$code', LocalStorageService.sanitize(updated));

      // Save to local inventory audit logs
      await LocalStorageService.saveLocalInventoryLog(fullAuditEntry);

      return true;
    } catch (e) {
      debugPrint('[MasterProformaService] Error editing proforma item: $e');
      return false;
    }
  }

  /// Edits an existing proforma item's name, type, and dose with mandatory audit trail.
  static Future<bool> editProformaItem({
    required String code,
    required String newName,
    required String newType,
    required String newDose,
    required Map<String, dynamic> auditLog,
  }) async {
    try {
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox(boxName);
      }
      final box = Hive.box(boxName);
      dynamic existing = box.get('proforma:$code');

      // Fallback search in default list if not yet customized in Hive
      if (existing == null) {
        for (final defItem in _defaultProformaList) {
          if (defItem['code'] == code) {
            existing = Map<String, dynamic>.from(defItem);
            break;
          }
        }
      }

      if (existing == null) return false;

      final updated = Map<String, dynamic>.from(existing is Map ? existing : {});
      final oldName = (updated['name'] ?? updated['formula'] ?? '').toString();
      final oldType = (updated['type'] ?? 'Tablet').toString();
      final oldDose = (updated['dose'] ?? '').toString();
      final cleanNewName = cleanBrandToFormula(newName);

      updated['name'] = cleanNewName;
      updated['formula'] = cleanNewName;
      updated['type'] = newType;
      updated['dose'] = newDose;
      updated['updatedAt'] = DateTime.now().toIso8601String();

      // Append to audit trail
      final List<Map<String, dynamic>> auditTrail = [];
      if (updated['auditTrail'] is List) {
        auditTrail.addAll((updated['auditTrail'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
      }
      final fullAuditEntry = {
        ...auditLog,
        'action': 'edit_proforma_medicine',
        'medicineCode': code,
        'oldName': oldName,
        'newName': cleanNewName,
        'oldType': oldType,
        'newType': newType,
        'oldDose': oldDose,
        'newDose': newDose,
        'timestamp': DateTime.now().toIso8601String(),
      };
      auditTrail.add(fullAuditEntry);
      updated['auditTrail'] = auditTrail;

      await box.put('proforma:$code', LocalStorageService.sanitize(updated));

      // Save to local inventory audit logs
      await LocalStorageService.saveLocalInventoryLog(fullAuditEntry);

      return true;
    } catch (e) {
      debugPrint('[MasterProformaService] Error editing proforma item: $e');
      return false;
    }
  }

  /// Returns all recorded audit logs for a proforma item.
  static List<Map<String, dynamic>> getAuditTrailForItem(String code) {
    try {
      if (Hive.isBoxOpen(boxName)) {
        final val = Hive.box(boxName).get('proforma:$code');
        if (val is Map && val['auditTrail'] is List) {
          return (val['auditTrail'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Converts any commercial brand name into its generic formula with brand name in brackets
  /// Converts any medicine name or brand into its standard canonical representation: Generic Formula (Popular Brand)
  static String cleanBrandToFormula(String input) {
    var text = input.trim();
    if (text.isEmpty) return text;

    // Iteratively unwrap and strip ALL outer and nested parentheses
    while (text.contains('(') && text.contains(')')) {
      final prev = text;
      text = text.replaceAll(RegExp(r'\s*\([^()]*\)'), '').trim();
      if (text == prev) break;
    }
    // Also remove any remaining unclosed or mismatched parens
    text = text.replaceAll('(', '').replaceAll(')', '').trim();

    final lower = text.toLowerCase().trim();

    // Direct canonical mapping based on base formula/brand keyword
    if (lower.contains('amoxicillin') && (lower.contains('clav') || lower.contains('augmentin') || lower.contains('amclav') || lower.contains('curam'))) {
      return 'Co-Amoxiclav (Augmentin)';
    }
    if (lower.contains('amoxicillin') || lower.contains('amoxil')) {
      return 'Amoxicillin (Amoxil)';
    }
    if (lower.contains('paracetamol') || lower.contains('panadol') || lower.contains('calpol') || lower.contains('febrol') || lower.contains('disprol')) {
      if (lower.contains('caffeine') || lower.contains('extra')) {
        return 'Paracetamol + Caffeine (Panadol Extra)';
      }
      return 'Paracetamol (Panadol)';
    }
    if (lower.contains('metronidazole') || lower.contains('flagyl')) {
      if (lower.contains('diloxanide') || lower.contains('entamizole')) {
        return 'Metronidazole + Diloxanide (Entamizole)';
      }
      return 'Metronidazole (Flagyl)';
    }
    if (lower.contains('chlorpheniramine') || lower.contains('cpm')) {
      return 'Chlorpheniramine Maleate (CPM)';
    }
    if (lower.contains('pheniramine') || lower.contains('avil')) {
      return 'Pheniramine Maleate (Avil)';
    }
    if (lower.contains('aspirin') || lower.contains('disprin') || lower.contains('dispirin')) {
      return 'Aspirin (Disprin)';
    }
    if (lower.contains('loprin')) {
      return 'Aspirin (Loprin)';
    }
    if (lower.contains('ibuprofen') || lower.contains('brufen') || lower.contains('arofen')) {
      return 'Ibuprofen (Brufen)';
    }
    if (lower.contains('mefenamic') || lower.contains('ponstan')) {
      return 'Mefenamic Acid (Ponstan)';
    }
    if (lower.contains('diclofenac') || lower.contains('voltral') || lower.contains('voren') || lower.contains('dicloran')) {
      return 'Diclofenac Sodium (Voltral)';
    }
    if (lower.contains('hyoscine') || lower.contains('buscopan')) {
      return 'Hyoscine Butylbromide (Buscopan)';
    }
    if (lower.contains('dimenhydrinate') || lower.contains('gravinate')) {
      return 'Dimenhydrinate (Gravinate)';
    }
    if (lower.contains('drotaverine') || lower.contains('drotavorine') || lower.contains('no-spa') || lower.contains('nospa')) {
      return 'Drotaverine (No-Spa)';
    }
    if (lower.contains('prochlorperazine') || lower.contains('stemetil')) {
      return 'Prochlorperazine (Stemetil)';
    }
    if (lower.contains('serratiopeptidase') || lower.contains('danzen')) {
      return 'Serratiopeptidase (Danzen DS)';
    }
    if (lower.contains('metoclopramide') || lower.contains('metoclone') || lower.contains('maxolon')) {
      return 'Metoclopramide (Maxolon / Metoclone)';
    }
    if (lower.contains('omeprazole') || lower.contains('risek') || lower.contains('losec')) {
      return 'Omeprazole (Risek)';
    }
    if (lower.contains('esomeprazole') || lower.contains('nexum') || lower.contains('esom')) {
      return 'Esomeprazole (Nexum)';
    }
    if (lower.contains('cefixime') || lower.contains('cefspan')) {
      return 'Cefixime (Cefspan)';
    }
    if (lower.contains('ciprofloxacin') || lower.contains('novidat') || lower.contains('ciprox')) {
      return 'Ciprofloxacin (Novidat)';
    }
    if (lower.contains('levofloxacin') || lower.contains('leflox')) {
      return 'Levofloxacin (Leflox)';
    }
    if (lower.contains('azithromycin') || lower.contains('zithromax') || lower.contains('azomax')) {
      return 'Azithromycin (Zithromax)';
    }
    if (lower.contains('clarithromycin') || lower.contains('klaricid')) {
      return 'Clarithromycin (Klaricid)';
    }
    if (lower.contains('ceftriaxone') || lower.contains('rocephin') || lower.contains('epoceph')) {
      return 'Ceftriaxone (Rocephin)';
    }
    if (lower.contains('cetirizine') || lower.contains('rigix') || lower.contains('zyrtec')) {
      return 'Cetirizine (Rigix)';
    }
    if (lower.contains('loratadine') || lower.contains('clarityn') || lower.contains('softin')) {
      return 'Loratadine (Softin)';
    }
    if (lower.contains('fexofenadine') || lower.contains('fexo') || lower.contains('telfast')) {
      return 'Fexofenadine (Fexo)';
    }
    if (lower.contains('salbutamol') || lower.contains('ventolin')) {
      return 'Salbutamol (Ventolin)';
    }
    if (lower.contains('antacid') || lower.contains('mucaine') || lower.contains('digas') || lower.contains('simeco')) {
      return 'Antacid (Mucaine / Digas)';
    }
    if (lower.contains('ammonium chloride') || lower.contains('hydryllin')) {
      return 'Ammonium Chloride (Hydryllin)';
    }
    if (lower.contains('carminative') || lower.contains('gripe water')) {
      return 'Carminative Mixture (Gripe Water)';
    }
    if (lower.contains('dexamethasone') || lower.contains('decadron')) {
      return 'Dexamethasone (Decadron)';
    }
    if (lower.contains('ondansetron') || lower.contains('onset')) {
      return 'Ondansetron (Onset)';
    }
    if (lower.contains('folic acid') || lower.contains('folvite')) {
      return 'Folic Acid (Folvite)';
    }
    if (lower.contains('sunny') || lower.contains('adhesive') || lower.contains('first aid bandage')) {
      return 'Adhesive First Aid Bandage (Sunny Plast)';
    }
    if (lower.contains('pyodine') || lower.contains('povidone')) {
      return 'Povidone Iodine Solution (Pyodine)';
    }
    if (lower.contains('surbex') || (lower.contains('multivitamin') && lower.contains('zinc'))) {
      return 'Multivitamin + Zinc (Surbex-Z)';
    }
    if (lower.contains('polybion') || lower.contains('vitamin b complex') || lower.contains('becosules')) {
      return 'Vitamin B Complex (Polybion)';
    }
    if (lower.contains('ca-c') || lower.contains('cac-1000') || (lower.contains('calcium') && lower.contains('vitamin c'))) {
      return 'Calcium + Vitamin C + Vitamin D (Ca-C 1000)';
    }
    if (lower.contains('vitamin c') || lower.contains('cevicon') || lower.contains('cecon')) {
      return 'Vitamin C (Cevicon)';
    }
    if (lower.contains('vitamin d3') || lower.contains('indrop-d') || lower.contains('sunny d')) {
      return 'Vitamin D3 (Sunny D)';
    }
    if (lower.contains('doxycycline') || lower.contains('vibramycin')) {
      return 'Doxycycline (Vibramycin)';
    }
    if (lower.contains('oxytetracycline') || lower.contains('terramycin')) {
      return 'Oxytetracycline (Terramycin)';
    }
    if (lower.contains('indomethacin') || lower.contains('indocin')) {
      return 'Indomethacin (Indocin)';
    }
    if (lower.contains('lincomycin') || lower.contains('lincocin')) {
      return 'Lincomycin (Lincocin)';
    }
    if (lower.contains('ipratropium') || lower.contains('atrovent')) {
      return 'Ipratropium Bromide (Atrovent)';
    }
    if (lower.contains('nimesulide') || lower.contains('nise')) {
      return 'Nimesulide (Nise)';
    }

    return input.trim();
  }

  /// Sanitizes all saved stock items in Hive stockBox to generic formulas
  static Future<int> sanitizeAllSavedStockItems() async {
    int updatedCount = 0;
    try {
      if (!Hive.isBoxOpen(LocalStorageService.stockBox)) {
        await Hive.openBox(LocalStorageService.stockBox);
      }
      final box = Hive.box(LocalStorageService.stockBox);
      for (final key in box.keys.toList()) {
        final val = box.get(key);
        if (val is Map) {
          final item = Map<String, dynamic>.from(val);
          final rawName = item['name']?.toString() ?? '';
          final rawFormula = item['formula']?.toString() ?? '';

          final cleanName = cleanBrandToFormula(rawName);
          final cleanFormula = cleanBrandToFormula(rawFormula);

          if (cleanName != rawName || cleanFormula != rawFormula) {
            item['name'] = cleanName;
            item['formula'] = cleanFormula;
            await box.put(key, LocalStorageService.sanitize(item));
            updatedCount++;
          }
        }
      }
      if (updatedCount > 0) {
        debugPrint('[MasterProformaService] Sanitized $updatedCount items in stockBox to generic formulas.');
      }
    } catch (e) {
      debugPrint('[MasterProformaService] Error sanitizing saved stock items: $e');
    }
    return updatedCount;
  }
}
