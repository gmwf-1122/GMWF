// lib/services/local_token_service.dart
import 'package:flutter/foundation.dart';

import '../models/token.dart';
import 'local_storage_service.dart';

class LocalTokenService {
  static List<Token> getAllToday(String branchId) {
    final today = DateTime.now();
    final entries = LocalStorageService.getLocalEntries(branchId);

    final todayTokens = entries
        .map(Token.fromMap)
        .where((t) =>
            t.createdAt.year == today.year &&
            t.createdAt.month == today.month &&
            t.createdAt.day == today.day)
        .toList();

    if (kDebugMode) {
      debugPrint('Local tokens for today ($branchId): ${todayTokens.length}');
    }

    return todayTokens;
  }

  static Future<void> generateToken(Token token, String branchId) async {
    try {
      await LocalStorageService.saveEntryLocal(
        branchId,
        token.id,
        token.toMap(),
      );
      if (kDebugMode) {
        debugPrint('Token saved locally → ID: ${token.id}');
      }
    } catch (e) {
      debugPrint('Failed to save token locally: $e');
    }
  }

  static Token? getLatestToken(String branchId) {
    final tokens = getAllToday(branchId);
    if (tokens.isEmpty) return null;

    tokens.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return tokens.first;
  }
}