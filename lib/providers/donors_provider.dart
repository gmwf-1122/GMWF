// lib/providers/donors_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../services/donations_local_storage.dart';
import '../pages/donations/donations_shared.dart';

/// Streams donors for a specific branch (null for all).
final donorStreamProvider = StreamProvider.autoDispose.family<List<DonorRecord>, String?>((ref, branchId) {
  return DonationsLocalStorage.streamAllDonors(branchId);
});

/// Groups donors into households, runs heavy computation in background isolate.
Future<List<List<DonorRecord>>> _groupDonors(List<DonorRecord> donors) async {
  final Map<String, List<DonorRecord>> grouped = {};
  for (var d in donors) {
    final String key;
    if (d.householdId != null && d.householdId!.isNotEmpty) {
      key = 'hh-${d.householdId}';
    } else {
      final pNorm = d.phones.isNotEmpty ? d.phones.first.replaceAll(RegExp(r'\\D'), '') : '';
      key = pNorm.isEmpty ? 'individual-${d.id}' : 'ph-$pNorm';
    }
    grouped.putIfAbsent(key, () => []).add(d);
  }
  // Sort each household by creation date
  for (var list in grouped.values) {
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }
  final households = grouped.values.toList();
  households.sort((a, b) => a.first.name.toLowerCase().compareTo(b.first.name.toLowerCase()));
  return households;
}

/// Provider that returns grouped households for a branch.
final donorGroupsProvider = FutureProvider.autoDispose.family<List<List<DonorRecord>>, String?>((ref, branchId) async {
  final donors = await ref.watch(donorStreamProvider(branchId).future);
  // Use compute for heavy work
  return await compute(_groupDonors, donors);
});
