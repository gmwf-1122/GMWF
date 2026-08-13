// lib/utils/string_similarity_helper.dart

import 'dart:math';

class StringSimilarityHelper {
  /// Normalizes a string by converting to lowercase, removing non-alphanumeric characters,
  /// and trimming extra spaces.
  static String normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Calculates the Levenshtein distance between two strings.
  static int levenshteinDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    List<int> v0 = List<int>.generate(b.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(b.length + 1, 0);

    for (int i = 0; i < a.length; i++) {
      v1[0] = i + 1;

      for (int j = 0; j < b.length; j++) {
        int cost = (a[i] == b[j]) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }

      for (int j = 0; j <= b.length; j++) {
        v0[j] = v1[j];
      }
    }

    return v1[b.length];
  }

  /// Calculates normalized similarity ratio between two strings (0.0 to 1.0).
  /// 1.0 means exact match, 0.0 means completely different.
  static double calculateSimilarity(String s1, String s2) {
    final norm1 = normalize(s1);
    final norm2 = normalize(s2);

    if (norm1 == norm2) return 1.0;
    if (norm1.isEmpty || norm2.isEmpty) return 0.0;

    // Substring boost: If one normalized string is a substring of another and length > 3
    if (norm1.length >= 3 && norm2.contains(norm1)) {
      return max(0.85, 1.0 - ((norm2.length - norm1.length) / max(norm1.length, norm2.length)));
    }
    if (norm2.length >= 3 && norm1.contains(norm2)) {
      return max(0.85, 1.0 - ((norm1.length - norm2.length) / max(norm1.length, norm2.length)));
    }

    final distance = levenshteinDistance(norm1, norm2);
    final maxLen = max(norm1.length, norm2.length);

    if (maxLen == 0) return 1.0;
    return (1.0 - (distance / maxLen)).clamp(0.0, 1.0);
  }

  /// Finds top similar medicines from a list of candidate medicines.
  /// Each candidate item should be a Map containing at least 'name'.
  static List<Map<String, dynamic>> findSimilarMedicines(
    String inputName,
    List<Map<String, dynamic>> candidates, {
    double threshold = 0.60,
    int maxResults = 3,
  }) {
    if (inputName.trim().isEmpty) return [];

    final List<Map<String, dynamic>> matches = [];

    for (final cand in candidates) {
      final candName = (cand['name'] as String? ?? '').trim();
      if (candName.isEmpty) continue;

      final score = calculateSimilarity(inputName, candName);
      if (score >= threshold) {
        final itemWithScore = Map<String, dynamic>.from(cand);
        itemWithScore['_similarityScore'] = score;
        matches.add(itemWithScore);
      }
    }

    matches.sort((a, b) => ((b['_similarityScore'] as double? ?? 0.0))
        .compareTo((a['_similarityScore'] as double? ?? 0.0)));

    return matches.take(maxResults).toList();
  }
}
