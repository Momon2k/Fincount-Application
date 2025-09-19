import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/session.dart';

class ApiService {
  static const String _baseUrl = 'http://localhost:3000/api'; // Change to your Next.js URL
  static const Duration _timeout = Duration(seconds: 30);
  
  // Headers for API requests
  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // Headers with authentication token
  static Map<String, String> _headersWithAuth(String token) => {
    ..._headers,
    'Authorization': 'Bearer $token',
  };

  // Get base URL from environment or use default
  static String get baseUrl {
    try {
      return dotenv.env['API_BASE_URL'] ?? _baseUrl;
    } catch (e) {
      return _baseUrl;
    }
  }

  // Generic HTTP request handler
  static Future<http.Response> _makeRequest(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    bool requiresAuth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final requestHeaders = headers ?? (requiresAuth ? await _getAuthHeaders() : _headers);
    
    http.Response response;
    
    try {
      switch (method.toUpperCase()) {
        case 'GET':
          response = await http.get(uri, headers: requestHeaders).timeout(_timeout);
          break;
        case 'POST':
          response = await http.post(
            uri,
            headers: requestHeaders,
            body: body != null ? jsonEncode(body) : null,
          ).timeout(_timeout);
          break;
        case 'PUT':
          response = await http.put(
            uri,
            headers: requestHeaders,
            body: body != null ? jsonEncode(body) : null,
          ).timeout(_timeout);
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: requestHeaders).timeout(_timeout);
          break;
        default:
          throw Exception('Unsupported HTTP method: $method');
      }
      
      return response;
    } on SocketException {
      throw Exception('No internet connection');
    } on HttpException {
      throw Exception('HTTP error occurred');
    } catch (e) {
      throw Exception('Request failed: $e');
    }
  }

  // Get authentication headers
  static Future<Map<String, String>> _getAuthHeaders() async {
    final token = await AuthService.getToken();
    return token != null ? _headersWithAuth(token) : _headers;
  }

  // Authentication endpoints
  static Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _makeRequest(
      'POST',
      '/auth/login',
      body: {'email': email, 'password': password},
      requiresAuth: false,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await AuthService.saveToken(data['token']);
      return data;
    } else {
      throw Exception('Login failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> register(String email, String password, String name) async {
    final response = await _makeRequest(
      'POST',
      '/auth/register',
      body: {'email': email, 'password': password, 'name': name},
      requiresAuth: false,
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      await AuthService.saveToken(data['token']);
      return data;
    } else {
      throw Exception('Registration failed: ${response.body}');
    }
  }

  static Future<void> logout() async {
    await _makeRequest('POST', '/auth/logout');
    await AuthService.clearToken();
  }

  // Session endpoints
  static Future<Map<String, dynamic>> createSession(Session session) async {
    final response = await _makeRequest(
      'POST',
      '/sessions',
      body: session.toJson(),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to create session: ${response.body}');
    }
  }

  static Future<List<Session>> getAllSessions() async {
    final response = await _makeRequest('GET', '/sessions');

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Session.fromJson(json)).toList();
    } else {
      throw Exception('Failed to fetch sessions: ${response.body}');
    }
  }

  static Future<List<Session>> getBatchSessions(String batchId) async {
    final response = await _makeRequest('GET', '/sessions/batch/$batchId');

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Session.fromJson(json)).toList();
    } else {
      throw Exception('Failed to fetch batch sessions: ${response.body}');
    }
  }

  static Future<Session> updateSession(String sessionId, Session session) async {
    final response = await _makeRequest(
      'PUT',
      '/sessions/$sessionId',
      body: session.toJson(),
    );

    if (response.statusCode == 200) {
      return Session.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to update session: ${response.body}');
    }
  }

  static Future<void> deleteSession(String sessionId) async {
    final response = await _makeRequest('DELETE', '/sessions/$sessionId');

    if (response.statusCode != 200) {
      throw Exception('Failed to delete session: ${response.body}');
    }
  }

  // Batch endpoints
  static Future<Map<String, dynamic>> getAllBatches() async {
    final response = await _makeRequest('GET', '/batches');

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch batches: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> createBatch(Map<String, dynamic> batchData) async {
    final response = await _makeRequest(
      'POST',
      '/batches',
      body: batchData,
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to create batch: ${response.body}');
    }
  }

  // Image upload endpoint
  static Future<String> uploadImage(File imageFile, String sessionId) async {
    try {
      final uri = Uri.parse('$baseUrl/upload/image');
      final request = http.MultipartRequest('POST', uri);
      
      // Add authentication headers
      final authHeaders = await _getAuthHeaders();
      request.headers.addAll(authHeaders);
      
      // Add the image file
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );
      
      // Add session ID
      request.fields['sessionId'] = sessionId;
      
      final streamedResponse = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['imageUrl'];
      } else {
        throw Exception('Failed to upload image: ${response.body}');
      }
    } catch (e) {
      throw Exception('Image upload failed: $e');
    }
  }

  // Sync local data with server
  static Future<void> syncLocalData(List<Session> localSessions) async {
    try {
      final response = await _makeRequest(
        'POST',
        '/sync',
        body: {
          'sessions': localSessions.map((s) => s.toJson()).toList(),
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to sync data: ${response.body}');
      }
    } catch (e) {
      throw Exception('Data sync failed: $e');
    }
  }

  // Health check
  static Future<bool> checkConnection() async {
    try {
      final response = await _makeRequest(
        'GET',
        '/health',
        requiresAuth: false,
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}

// Authentication service for token management
class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> saveUserData(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(userData));
  }

  static Future<Map<String, dynamic>?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString(_userKey);
    if (userDataString != null) {
      return jsonDecode(userDataString);
    }
    return null;
  }
}
