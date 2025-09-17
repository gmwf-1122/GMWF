import 'dart:convert';
import 'package:http/http.dart' as http;

class RealtimeDatabaseService {
  final String baseUrl = 'https://gmwf-8fc4c-default-rtdb.firebaseio.com';

  Uri _json(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$baseUrl/$path.json');
    return query != null ? uri.replace(queryParameters: query) : uri;
  }

  Map<String, String> get _headers => {'Content-Type': 'application/json'};

  Future<Map<String, dynamic>?> getPath(String path) async {
    final res = await http.get(_json(path), headers: _headers).timeout(
          const Duration(seconds: 8),
        );
    if (res.statusCode == 200 && res.body != 'null') {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    return null;
  }

  Future<dynamic> getValue(String path) async {
    final res = await http.get(_json(path), headers: _headers).timeout(
          const Duration(seconds: 8),
        );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return null;
  }

  Future<void> put(String path, dynamic value) async =>
      await http.put(_json(path), headers: _headers, body: jsonEncode(value));

  Future<String?> post(String path, dynamic value) async {
    final res = await http.post(_json(path),
        headers: _headers, body: jsonEncode(value));
    if (res.statusCode == 200 || res.statusCode == 201) {
      final data = jsonDecode(res.body);
      return data['name'];
    }
    return null;
  }

  Future<void> patch(String path, Map<String, dynamic> value) async =>
      await http.patch(_json(path), headers: _headers, body: jsonEncode(value));

  Future<void> delete(String path) async =>
      await http.delete(_json(path), headers: _headers);

  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final q = {'orderBy': '"email"', 'equalTo': '"$email"'};
    final res = await http.get(_json('users', q), headers: _headers).timeout(
          const Duration(seconds: 10),
        );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      if (data == null || data == 'null' || (data as Map).isEmpty) return null;
      return data as Map<String, dynamic>;
    }
    return null;
  }
}
