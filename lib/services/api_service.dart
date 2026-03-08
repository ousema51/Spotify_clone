import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  Future<Map<String, String>> _headers({bool requiresAuth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (requiresAuth) {
      final token = await _getToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Future<Map<String, dynamic>> get(String path,
      {bool requiresAuth = true}) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}$path');
      final response = await http.get(uri,
          headers: await _headers(requiresAuth: requiresAuth));
      return _handleResponse(response);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
      {bool requiresAuth = true}) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}$path');
      final response = await http.post(uri,
          headers: await _headers(requiresAuth: requiresAuth),
          body: jsonEncode(body));
      return _handleResponse(response);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body,
      {bool requiresAuth = true}) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}$path');
      final response = await http.put(uri,
          headers: await _headers(requiresAuth: requiresAuth),
          body: jsonEncode(body));
      return _handleResponse(response);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> delete(String path,
      {bool requiresAuth = true}) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}$path');
      final response = await http.delete(uri,
          headers: await _headers(requiresAuth: requiresAuth));
      return _handleResponse(response);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return data;
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Request failed',
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Invalid server response (status ${response.statusCode})',
      };
    }
  }
}
