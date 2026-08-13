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
      'name': 'Paracetamol',
      'formula': 'Paracetamol',
      'type': 'Tablet',
      'dose': '500 mg',
      'defaultPrice': 2.50,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-PARA-CAF',
      'name': 'Paracetamol + Caffeine',
      'formula': 'Paracetamol + Caffeine',
      'type': 'Tablet',
      'dose': '500 mg',
      'defaultPrice': 3.50,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-PARA-SYR',
      'name': 'Paracetamol',
      'formula': 'Paracetamol',
      'type': 'Syrup',
      'dose': '120 ml',
      'defaultPrice': 80.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-PARA-INJ-100',
      'name': 'Paracetamol Injection / Infusion',
      'formula': 'Paracetamol',
      'type': 'Injection',
      'dose': '100 ml (1000 mg)',
      'defaultPrice': 120.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-PARA-INJ-2ML',
      'name': 'Paracetamol Injection',
      'formula': 'Paracetamol',
      'type': 'Injection',
      'dose': '2 ml (150 mg/ml)',
      'defaultPrice': 35.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-AMX-250',
      'name': 'Amoxicillin',
      'formula': 'Amoxicillin',
      'type': 'Capsule',
      'dose': '250 mg',
      'defaultPrice': 10.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-AMX-500',
      'name': 'Amoxicillin',
      'formula': 'Amoxicillin',
      'type': 'Capsule',
      'dose': '500 mg',
      'defaultPrice': 18.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-AMX-SYR',
      'name': 'Amoxicillin',
      'formula': 'Amoxicillin',
      'type': 'Syrup',
      'dose': '120 ml',
      'defaultPrice': 110.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-CEF-400',
      'name': 'Cefixime',
      'formula': 'Cefixime',
      'type': 'Capsule',
      'dose': '400 mg',
      'defaultPrice': 45.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-CEF-SYR',
      'name': 'Cefixime',
      'formula': 'Cefixime',
      'type': 'Syrup',
      'dose': '100 ml',
      'defaultPrice': 220.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-FLG-400',
      'name': 'Flagyl',
      'formula': 'Flagyl',
      'type': 'Tablet',
      'dose': '400 mg',
      'defaultPrice': 4.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-FLG-SYR',
      'name': 'Flagyl',
      'formula': 'Flagyl',
      'type': 'Syrup',
      'dose': '90 ml',
      'defaultPrice': 65.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-OMP-20',
      'name': 'Omeprazole',
      'formula': 'Omeprazole',
      'type': 'Capsule',
      'dose': '20 mg',
      'defaultPrice': 15.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-OMP-40',
      'name': 'Omeprazole',
      'formula': 'Omeprazole',
      'type': 'Capsule',
      'dose': '40 mg',
      'defaultPrice': 25.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-OMP-IV',
      'name': 'Omeprazole IV',
      'formula': 'Omeprazole',
      'type': 'Injection',
      'dose': '40 mg',
      'defaultPrice': 180.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-AUG-625',
      'name': 'Co-Amoxiclav',
      'formula': 'Co-Amoxiclav',
      'type': 'Tablet',
      'dose': '625 mg',
      'defaultPrice': 30.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-AUG-1G',
      'name': 'Co-Amoxiclav',
      'formula': 'Co-Amoxiclav',
      'type': 'Tablet',
      'dose': '1 g',
      'defaultPrice': 50.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-AUG-SYR',
      'name': 'Co-Amoxiclav',
      'formula': 'Co-Amoxiclav',
      'type': 'Syrup',
      'dose': '90 ml',
      'defaultPrice': 240.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-IBU-400',
      'name': 'Ibuprofen',
      'formula': 'Ibuprofen',
      'type': 'Tablet',
      'dose': '400 mg',
      'defaultPrice': 5.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-IBU-SYR',
      'name': 'Ibuprofen',
      'formula': 'Ibuprofen',
      'type': 'Syrup',
      'dose': '120 ml',
      'defaultPrice': 75.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-DMH-50',
      'name': 'Dimenhydrinate',
      'formula': 'Dimenhydrinate',
      'type': 'Tablet',
      'dose': '50 mg',
      'defaultPrice': 2.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-DMH-SYR',
      'name': 'Dimenhydrinate',
      'formula': 'Dimenhydrinate',
      'type': 'Syrup',
      'dose': '120 ml',
      'defaultPrice': 60.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-DMH-INJ',
      'name': 'Dimenhydrinate',
      'formula': 'Dimenhydrinate',
      'type': 'Injection',
      'dose': '50 mg',
      'defaultPrice': 35.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-DEX-INJ',
      'name': 'Dexamethasone',
      'formula': 'Dexamethasone',
      'type': 'Injection',
      'dose': '5 mg',
      'defaultPrice': 40.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-OND-INJ',
      'name': 'Ondansetron',
      'formula': 'Ondansetron',
      'type': 'Injection',
      'dose': '4 mg',
      'defaultPrice': 55.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-CEF-1G',
      'name': 'Ceftriaxone',
      'formula': 'Ceftriaxone',
      'type': 'Injection',
      'dose': '1 g',
      'defaultPrice': 150.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-CEF-500M',
      'name': 'Ceftriaxone',
      'formula': 'Ceftriaxone',
      'type': 'Injection',
      'dose': '500 mg',
      'defaultPrice': 110.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-NS-1000',
      'name': '0.9% NaCl (Normal Saline)',
      'formula': '0.9% NaCl',
      'type': 'Drip',
      'dose': '1000 ml',
      'defaultPrice': 120.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-DS-1000',
      'name': '5% Dextrose + 0.9% NaCl',
      'formula': '5% Dextrose + 0.9% NaCl',
      'type': 'Drip',
      'dose': '1000 ml',
      'defaultPrice': 130.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-RL-1000',
      'name': 'Ringer Solution',
      'formula': 'Ringer Solution',
      'type': 'Drip',
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
      'name': 'Multivitamin + Zinc',
      'formula': 'Multivitamin + Zinc',
      'type': 'Tablet',
      'dose': 'Standard',
      'defaultPrice': 12.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-VITC-500',
      'name': 'Vitamin C',
      'formula': 'Vitamin C',
      'type': 'Tablet',
      'dose': '500 mg',
      'defaultPrice': 5.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-CAL-500',
      'name': 'Calcium',
      'formula': 'Calcium',
      'type': 'Tablet',
      'dose': '500 mg',
      'defaultPrice': 8.00,
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
      'name': 'Mefenamic Acid',
      'formula': 'Mefenamic Acid',
      'type': 'Tablet',
      'dose': '250 mg',
      'defaultPrice': 3.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-MEF-500',
      'name': 'Mefenamic Acid',
      'formula': 'Mefenamic Acid',
      'type': 'Tablet',
      'dose': '500 mg',
      'defaultPrice': 6.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-ENT-TAB',
      'name': 'Flagyl + Diloxanide',
      'formula': 'Flagyl + Diloxanide',
      'type': 'Tablet',
      'dose': '250 mg / 375 mg',
      'defaultPrice': 8.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-DRT-40',
      'name': 'Drotaverine',
      'formula': 'Drotaverine',
      'type': 'Tablet',
      'dose': '40 mg',
      'defaultPrice': 5.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-HYO-10',
      'name': 'Hyoscine Butylbromide',
      'formula': 'Hyoscine Butylbromide',
      'type': 'Tablet',
      'dose': '10 mg',
      'defaultPrice': 4.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-HYO-INJ',
      'name': 'Hyoscine Butylbromide',
      'formula': 'Hyoscine Butylbromide',
      'type': 'Injection',
      'dose': '20 mg',
      'defaultPrice': 40.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-PHE-INJ',
      'name': 'Pheniramine Maleate',
      'formula': 'Pheniramine Maleate',
      'type': 'Injection',
      'dose': '50 mg',
      'defaultPrice': 30.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-ASP-300',
      'name': 'Aspirin',
      'formula': 'Aspirin',
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
      'name': 'Diclofenac Sodium Injection',
      'formula': 'Diclofenac Sodium',
      'type': 'Injection',
      'dose': '75 mg / 3 ml',
      'defaultPrice': 30.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-TRM-INJ',
      'name': 'Tramadol Hydrochloride Injection',
      'formula': 'Tramadol',
      'type': 'Injection',
      'dose': '100 mg / 2 ml',
      'defaultPrice': 45.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-HYD-INJ',
      'name': 'Hydrocortisone Sodium Succinate',
      'formula': 'Hydrocortisone',
      'type': 'Injection',
      'dose': '100 mg',
      'defaultPrice': 65.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-MTC-INJ',
      'name': 'Metoclopramide Injection',
      'formula': 'Metoclopramide',
      'type': 'Injection',
      'dose': '10 mg / 2 ml',
      'defaultPrice': 25.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-CIP-DRP',
      'name': 'Ciprofloxacin Infusion',
      'formula': 'Ciprofloxacin',
      'type': 'Drip',
      'dose': '100 ml (200 mg)',
      'defaultPrice': 140.00,
      'isProformaMaster': true,
    },
    // ── Brufen 200ml Syrup ───────────────────────────────────────────────
    {
      'code': 'MED-BRF-SYR',
      'name': 'Brufen',
      'formula': 'Brufen',
      'type': 'Syrup',
      'dose': '200 ml',
      'defaultPrice': 120.00,
      'isProformaMaster': true,
    },
    // ── Metoclone 4mg (Tablet, Capsule, Injection, Syrup) ───────────────
    {
      'code': 'MED-METCL-TAB',
      'name': 'Metoclone',
      'formula': 'Metoclone',
      'type': 'Tablet',
      'dose': '4 mg',
      'defaultPrice': 5.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-METCL-CAP',
      'name': 'Metoclone',
      'formula': 'Metoclone',
      'type': 'Capsule',
      'dose': '4 mg',
      'defaultPrice': 8.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-METCL-INJ',
      'name': 'Metoclone Injection',
      'formula': 'Metoclone',
      'type': 'Injection',
      'dose': '4 mg',
      'defaultPrice': 30.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-METCL-SYR',
      'name': 'Metoclone',
      'formula': 'Metoclone',
      'type': 'Syrup',
      'dose': '60 ml',
      'defaultPrice': 70.00,
      'isProformaMaster': true,
    },
    // ── Additional Requested Proforma Items ──────────────────────────────
    {
      'code': 'MED-CPM-4',
      'name': 'Chlorpheniramine Maleate',
      'formula': 'Chlorpheniramine Maleate',
      'type': 'Tablet',
      'dose': '4 mg',
      'defaultPrice': 2.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-VBC-TAB',
      'name': 'Vitamin B Complex',
      'formula': 'Vitamin B Complex',
      'type': 'Tablet',
      'dose': 'Standard',
      'defaultPrice': 4.00,
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
      'name': 'Prochlorperazine',
      'formula': 'Prochlorperazine',
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
      'code': 'MED-SRP-10',
      'name': 'Serratiopeptidase',
      'formula': 'Serratiopeptidase',
      'type': 'Tablet',
      'dose': '10 mg',
      'defaultPrice': 8.00,
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
      'name': 'Antacid',
      'formula': 'Antacid',
      'type': 'Syrup',
      'dose': '120 ml',
      'defaultPrice': 85.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-AMC-SYR',
      'name': 'Ammonium Chloride',
      'formula': 'Ammonium Chloride',
      'type': 'Syrup',
      'dose': '120 ml',
      'defaultPrice': 75.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-CRM-SYR',
      'name': 'Carminative Mixture',
      'formula': 'Carminative Mixture',
      'type': 'Syrup',
      'dose': '120 ml',
      'defaultPrice': 65.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-LIN-INJ',
      'name': 'Lincomycin',
      'formula': 'Lincomycin',
      'type': 'Injection',
      'dose': '600 mg / 2 ml',
      'defaultPrice': 45.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-CYN-INJ',
      'name': 'Cyanocobalamin',
      'formula': 'Cyanocobalamin',
      'type': 'Injection',
      'dose': '1000 mcg',
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
      'name': 'Sunny Plast',
      'formula': 'Sunny Plast',
      'type': 'Dressing Item',
      'dose': 'Standard',
      'defaultPrice': 5.00,
      'isProformaMaster': true,
    },
    {
      'code': 'EQUIP-PYD-SOL',
      'name': 'Pyodine Solution',
      'formula': 'Pyodine Solution',
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
      'type': 'Drip',
      'dose': '100 ml',
      'defaultPrice': 60.00,
      'isProformaMaster': true,
    },
    {
      'code': 'MED-NS-500',
      'name': '0.9% NaCl (Normal Saline)',
      'formula': '0.9% NaCl (Normal Saline)',
      'type': 'Drip',
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
      'type': 'Drip',
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
}
