import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Lightweight, ultra-fast direct Firestore REST transport for querying branch records.
/// Completely immune to Windows Firebase C++ SDK lockups, LanFirestoreGate offline disables,
/// and connectivity false-negatives.
class FirestoreRestService {
  FirestoreRestService._();
  static final FirestoreRestService instance = FirestoreRestService._();

  static const String projectId = 'gmwf-8fc4c';
  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 15);

  /// Decodes raw Firestore REST JSON field types (stringValue, integerValue, etc.) into clean Dart objects.
  static dynamic decodeFirestoreValue(dynamic val) {
    if (val == null || val is! Map) return null;
    if (val.containsKey('stringValue')) return val['stringValue'];
    if (val.containsKey('integerValue')) return int.tryParse(val['integerValue'].toString()) ?? 0;
    if (val.containsKey('doubleValue')) return double.tryParse(val['doubleValue'].toString()) ?? 0.0;
    if (val.containsKey('booleanValue')) return val['booleanValue'] == true;
    if (val.containsKey('timestampValue')) return val['timestampValue'];
    if (val.containsKey('nullValue')) return null;
    if (val.containsKey('mapValue')) {
      final fields = val['mapValue']?['fields'] as Map<String, dynamic>?;
      if (fields == null) return <String, dynamic>{};
      return fields.map((k, v) => MapEntry(k, decodeFirestoreValue(v)));
    }
    if (val.containsKey('arrayValue')) {
      final list = val['arrayValue']?['values'] as List?;
      if (list == null) return <dynamic>[];
      return list.map((v) => decodeFirestoreValue(v)).toList();
    }
    return null;
  }

  /// Converts a single Firestore REST document JSON into a standard `Map<String, dynamic>`.
  static Map<String, dynamic> decodeDocument(Map<String, dynamic> docJson) {
    final fields = docJson['fields'] as Map<String, dynamic>? ?? {};
    final res = <String, dynamic>{};
    for (final entry in fields.entries) {
      res[entry.key] = decodeFirestoreValue(entry.value);
    }
    final name = docJson['name']?.toString() ?? '';
    if (name.isNotEmpty) {
      res['id'] = name.split('/').last;
    }
    return res;
  }

  /// Fetches tokens for a specific branch, date/campDocKey, and queue type via REST.
  Future<List<Map<String, dynamic>>> fetchSerials({
    required String branchId,
    required String campDocKey,
    required String queueType,
  }) async {
    try {
      if (kIsWeb) return const []; // dart:io HttpClient is unavailable on web
      final normBranch = branchId.toLowerCase().trim();
      final url = 'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/branches/$normBranch/serials/$campDocKey/$queueType?pageSize=300';
      final req = await _client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
        final json = jsonDecode(body) as Map<String, dynamic>;
        final docs = (json['documents'] as List?) ?? [];
        final list = <Map<String, dynamic>>[];
        for (final doc in docs) {
          if (doc is Map<String, dynamic>) {
            final d = decodeDocument(doc);
            d['branchId'] ??= normBranch;
            list.add(d);
          }
        }
        return list;
      }
    } catch (e) {
      debugPrint('[FirestoreRestService] Error fetching serials for $branchId/$campDocKey/$queueType: $e');
    }
    return const <Map<String, dynamic>>[];
  }

  /// Fetches dispensary records for a specific branch and dateKey via REST.
  Future<List<Map<String, dynamic>>> fetchDispensary({
    required String branchId,
    required String dateKey,
  }) async {
    try {
      if (kIsWeb) return const []; // dart:io HttpClient is unavailable on web
      final normBranch = branchId.toLowerCase().trim();
      final url = 'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/branches/$normBranch/dispensary/$dateKey/$dateKey?pageSize=300';
      final req = await _client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
        final json = jsonDecode(body) as Map<String, dynamic>;
        final docs = (json['documents'] as List?) ?? [];
        final list = <Map<String, dynamic>>[];
        for (final doc in docs) {
          if (doc is Map<String, dynamic>) {
            final d = decodeDocument(doc);
            d['branchId'] ??= normBranch;
            list.add(d);
          }
        }
        return list;
      }
    } catch (e) {
      debugPrint('[FirestoreRestService] Error fetching dispensary for $branchId/$dateKey: $e');
    }
    return const <Map<String, dynamic>>[];
  }
}
