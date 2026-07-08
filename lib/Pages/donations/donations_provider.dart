// lib/pages/donations/donations_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../models/donation_models.dart';
import '../../services/donations_local_storage.dart';
import 'donations_shared.dart'; // for isolate processing function

/// Arguments passed to the isolate for processing donations.
class ProcessArgs {
  final List<DonationRecord> raw;
  final Comparator<DonationRecord> sortComparator;
  final bool Function(DonationRecord) filterPredicate;

  ProcessArgs({
    required this.raw,
    required this.sortComparator,
    required this.filterPredicate,
  });
}

/// State holding current sort and filter settings.
class DonationsSortFilterNotifier extends StateNotifier<DonationsSortFilterState> {
  DonationsSortFilterNotifier() : super(DonationsSortFilterState.initial());

  void setSortByDateDesc() {
    state = state.copyWith(
      sortComparator: (a, b) => b.date.compareTo(a.date),
    );
  }

  void setSortByAmountDesc() {
    state = state.copyWith(
      sortComparator: (a, b) => (b.amount ?? 0).compareTo(a.amount ?? 0),
    );
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }
}

class DonationsSortFilterState {
  final Comparator<DonationRecord> sortComparator;
  final String searchQuery;

  DonationsSortFilterState({
    required this.sortComparator,
    required this.searchQuery,
  });

  factory DonationsSortFilterState.initial() => DonationsSortFilterState(
        sortComparator: (a, b) => b.date.compareTo(a.date),
        searchQuery: '',
      );

  DonationsSortFilterState copyWith({
    Comparator<DonationRecord>? sortComparator,
    String? searchQuery,
  }) =>
      DonationsSortFilterState(
        sortComparator: sortComparator ?? this.sortComparator,
        searchQuery: searchQuery ?? this.searchQuery,
      );
}

/// Provider for the sort/filter notifier.
final donationsSortFilterProvider =
    StateNotifierProvider<DonationsSortFilterNotifier, DonationsSortFilterState>(
        (ref) => DonationsSortFilterNotifier());

/// Provider family to fetch a page of donations.
/// pageIndex starts at 0, pageSize is fixed (e.g., 40).
final donationsPageProvider = FutureProvider.family<List<DonationRecord>, int>(
    (ref, pageIndex) async {
  const int pageSize = 40;
  final int offset = pageIndex * pageSize;
  final String branchId = ref.watch(donationsDashboardBranchProvider);

  // Fetch raw donations for the branch (could be all donors)
  final List<DonationRecord> raw = await DonationsLocalStorage.fetchPage(
    branchId: branchId,
    offset: offset,
    limit: pageSize,
  );

  final sortFilter = ref.watch(donationsSortFilterProvider);

  // Build filter predicate based on search query
  bool Function(DonationRecord) predicate = (_) => true;
  final query = sortFilter.searchQuery.toLowerCase().trim();
  if (query.isNotEmpty) {
    predicate = (d) =>
        d.donorName.toLowerCase().contains(query) ||
        (d.phone?.toLowerCase().contains(query) ?? false);
  }

  // Process sorting and filtering off‑the‑main‑thread.
  final List<DonationRecord> processed = await compute(
    _processDonations,
    ProcessArgs(
      raw: raw,
      sortComparator: sortFilter.sortComparator,
      filterPredicate: predicate,
    ),
  );

  return processed;
});

/// Provider exposing the current branch context for pagination.
final donationsDashboardBranchProvider = Provider<String>((ref) => 'all');

/// Isolate worker that applies filter then sorting.
List<DonationRecord> _processDonations(ProcessArgs args) {
  final filtered = args.raw.where(args.filterPredicate).toList();
  filtered.sort(args.sortComparator);
  return filtered;
}
