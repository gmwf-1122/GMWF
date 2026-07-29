import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gmwf/pages/donations/donations_shared.dart';

void main() {
  test('buildReceiptPdfSync generates exactly one page receipt WITH notes', () async {
    final testData = <String, dynamic>{
      'categoryId': 'gmwf',
      'donorName': 'A very long donor name to test text wrapping and height issues on small screens',
      'branchName': 'Gulzar-e-Madina Welfare Foundation Head Office',
      'branchId': 'hq',
      'recordedBy': 'Muhammad Ahmad Raza Al-Azhari',
      'paymentMethod': 'Bank Deposit / Online Transfer',
      'notes': 'This is a test receipt remarks. It is somewhat long to test the space constraints of the single column ticket layout on a small page.',
      'subtypeId': 'zakat',
      'gmwfSubCategoryId': 'general',
      'date': '2026-06-23T12:00:00Z',
      'entryType': 'cash',
      'amount': 250000.0,
      '_ytdTotal': 750000.0,
    };

    final pdfBytes = await buildReceiptPdfSync(testData);
    final pdfText = String.fromCharCodes(pdfBytes);
    final pageRegex = RegExp(r'/Type\s*/Page\b');
    final matches = pageRegex.allMatches(pdfText);
    final pageCount = matches.length;

    print('WITH notes PDF Page Count: $pageCount');
    expect(pageCount, equals(1), reason: 'The receipt PDF must have exactly one page!');
  });

  test('buildReceiptPdfSync generates exactly one page receipt WITHOUT notes', () async {
    final testData = <String, dynamic>{
      'categoryId': 'gmwf',
      'donorName': 'A very long donor name to test text wrapping and height issues on small screens',
      'branchName': 'Gulzar-e-Madina Welfare Foundation Head Office',
      'branchId': 'hq',
      'recordedBy': 'Muhammad Ahmad Raza Al-Azhari',
      'paymentMethod': 'Bank Deposit / Online Transfer',
      'notes': '', // Empty notes
      'subtypeId': 'zakat',
      'gmwfSubCategoryId': 'general',
      'date': '2026-06-23T12:00:00Z',
      'entryType': 'cash',
      'amount': 250000.0,
      '_ytdTotal': 750000.0,
    };

    final pdfBytes = await buildReceiptPdfSync(testData);
    final pdfText = String.fromCharCodes(pdfBytes);
    final pageRegex = RegExp(r'/Type\s*/Page\b');
    final matches = pageRegex.allMatches(pdfText);
    final pageCount = matches.length;

    print('WITHOUT notes PDF Page Count: $pageCount');
    expect(pageCount, equals(1), reason: 'The receipt PDF must have exactly one page!');
  });
}
