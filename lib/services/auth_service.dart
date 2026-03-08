import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final ApiService _api = ApiService();
  static const String _tokenKey = 'auth_token';
  static const String _usernameKey = 'username';

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> _saveToken(String token, String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_usernameKey, username);
  }

  Future<void> _clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_usernameKey);
  }

  Future<Map<String, dynamic>> register(
      String username, String password) async {
    final result = await _api.post(
      '/auth/register',
      {'username': username, 'password': password},
      requiresAuth: false,
    );
    if (result['success'] == true && result['data'] != null) {
      final token = result['data']['token'] as String?;
      if (token != null) {
        await _saveToken(token, username);
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final result = await _api.post(
      '/auth/login',
      {'username': username, 'password': password},
      requiresAuth: false,
    );
    if (result['success'] == true && result['data'] != null) {
      final token = result['data']['token'] as String?;
      if (token != null) {
        await _saveToken(token, username);
      }
    }
    return result;
  }

  Future<void> logout() async {
    await _api.post('/auth/logout', {});
    await _clearToken();
  }

  Future<Map<String, dynamic>> getMe() async {
    return _api.get('/auth/me');
  }
}
