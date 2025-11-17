import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_interceptor/http_interceptor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/session.dart';
import '../models/user_model.dart';
import '../models/batch_model.dart';

// HTTP Logging Interceptor
class LoggingInterceptor implements InterceptorContract {
  @override
  Future<BaseRequest> interceptRequest({required BaseRequest request}) async {
    print(
        '\n╔════════════════════════════════════════════════════════════════');
    print('║ 🚀 API REQUEST');
    print('╠════════════════════════════════════════════════════════════════');
    print('║ Method: ${request.method}');
    print('║ URL: ${request.url}');
    print('║ Headers: ${request.headers}');

    if (request is Request) {
      if (request.body.isNotEmpty) {
        try {
          final prettyJson =
              JsonEncoder.withIndent('  ').convert(jsonDecode(request.body));
          print('║ Body:\n$prettyJson');
        } catch (e) {
          print('║ Body: ${request.body}');
        }
      }
    }
    print(
        '╚════════════════════════════════════════════════════════════════\n');
    return request;
  }

  @override
  Future<BaseResponse> interceptResponse(
      {required BaseResponse response}) async {
    print(
        '\n╔════════════════════════════════════════════════════════════════');
    print('║ 📥 API RESPONSE');
    print('╠════════════════════════════════════════════════════════════════');
    print('║ Status Code: ${response.statusCode}');
    print('║ URL: ${response.request?.url}');
    print('║ Headers: ${response.headers}');

    if (response is Response) {
      if (response.body.isNotEmpty) {
        try {
          final prettyJson =
              JsonEncoder.withIndent('  ').convert(jsonDecode(response.body));
          print('║ Response Body:\n$prettyJson');
        } catch (e) {
          print('║ Response Body: ${response.body}');
        }
      }
    }
    print(
        '╚════════════════════════════════════════════════════════════════\n');
    return response;
  }

  @override
  Future<bool> shouldInterceptRequest() async => true;

  @override
  Future<bool> shouldInterceptResponse() async => true;
}

class ApiService {
  // Create HTTP client with interceptor
  static final _client = InterceptedClient.build(
    interceptors: [LoggingInterceptor()],
    requestTimeout: ApiConfig.timeout,
  );

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

  // Get base URL from config
  static String get baseUrl {
    print('🌐 Using API Base URL: ${ApiConfig.baseUrl}');
    return ApiConfig.baseUrl;
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
    final requestHeaders =
        headers ?? (requiresAuth ? await _getAuthHeaders() : _headers);

    print('⏱️ Starting ${method.toUpperCase()} request to: $endpoint');
    final startTime = DateTime.now();

    http.Response response;

    try {
      switch (method.toUpperCase()) {
        case 'GET':
          response = await _client.get(uri, headers: requestHeaders);
          break;
        case 'POST':
          response = await _client.post(
            uri,
            headers: requestHeaders,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        case 'PUT':
          response = await _client.put(
            uri,
            headers: requestHeaders,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        case 'DELETE':
          response = await _client.delete(uri, headers: requestHeaders);
          break;
        default:
          throw Exception('Unsupported HTTP method: $method');
      }

      final duration = DateTime.now().difference(startTime);
      print('✅ Request completed in ${duration.inMilliseconds}ms');

      return response;
    } on SocketException catch (e) {
      print('❌ No internet connection: $e');
      throw Exception('No internet connection');
    } on HttpException catch (e) {
      print('❌ HTTP error occurred: $e');
      throw Exception('HTTP error occurred');
    } catch (e) {
      print('❌ Request failed: $e');
      throw Exception('Request failed: $e');
    }
  }

  // Get authentication headers
  static Future<Map<String, String>> _getAuthHeaders() async {
    final token = await AuthService.getToken();
    if (token != null) {
      print('🔐 Using authentication token');
    } else {
      print('⚠️ No authentication token found');
    }
    return token != null ? _headersWithAuth(token) : _headers;
  }

  // Authentication endpoints
  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    print('🔑 Attempting login for: $email');
    final response = await _makeRequest(
      'POST',
      '/auth/login',
      body: {'email': email, 'password': password},
      requiresAuth: false,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await AuthService.saveToken(data['token']);
      print('✅ Login successful');
      return data;
    } else {
      print('❌ Login failed with status: ${response.statusCode}');
      throw Exception('Login failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> register(
      String email, String password, String name) async {
    print('📝 Attempting registration for: $email');
    final response = await _makeRequest(
      'POST',
      '/auth/register',
      body: {'email': email, 'password': password, 'name': name},
      requiresAuth: false,
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      await AuthService.saveToken(data['token']);
      print('✅ Registration successful');
      return data;
    } else {
      print('❌ Registration failed with status: ${response.statusCode}');
      throw Exception('Registration failed: ${response.body}');
    }
  }

  static Future<void> logout() async {
    print('🚪 Logging out...');
    await _makeRequest('POST', '/auth/logout');
    await AuthService.clearToken();
    print('✅ Logout successful');
  }

  // Session endpoints
  static Future<Map<String, dynamic>> createSession(Session session) async {
    print('📊 Creating new session...');
    final response = await _makeRequest(
      'POST',
      '/sessions',
      body: session.toJson(),
    );

    if (response.statusCode == 201) {
      print('✅ Session created successfully');
      return jsonDecode(response.body);
    } else {
      print('❌ Failed to create session: ${response.statusCode}');
      throw Exception('Failed to create session: ${response.body}');
    }
  }

  static Future<List<Session>> getAllSessions() async {
    print('📋 Fetching all sessions...');
    final response = await _makeRequest('GET', '/sessions');

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      print('✅ Retrieved ${data.length} sessions');
      return data.map((json) => Session.fromJson(json)).toList();
    } else {
      print('❌ Failed to fetch sessions: ${response.statusCode}');
      throw Exception('Failed to fetch sessions: ${response.body}');
    }
  }

  static Future<List<Session>> getBatchSessions(String batchId) async {
    print('📋 Fetching sessions for batch: $batchId');
    final response = await _makeRequest('GET', '/sessions/batch/$batchId');

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      print('✅ Retrieved ${data.length} sessions for batch');
      return data.map((json) => Session.fromJson(json)).toList();
    } else {
      print('❌ Failed to fetch batch sessions: ${response.statusCode}');
      throw Exception('Failed to fetch batch sessions: ${response.body}');
    }
  }

  static Future<Session> updateSession(
      String sessionId, Session session) async {
    print('✏️ Updating session: $sessionId');
    final response = await _makeRequest(
      'PUT',
      '/sessions/$sessionId',
      body: session.toJson(),
    );

    if (response.statusCode == 200) {
      print('✅ Session updated successfully');
      return Session.fromJson(jsonDecode(response.body));
    } else {
      print('❌ Failed to update session: ${response.statusCode}');
      throw Exception('Failed to update session: ${response.body}');
    }
  }

  static Future<void> deleteSession(String sessionId) async {
    print('🗑️ Deleting session: $sessionId');
    final response = await _makeRequest('DELETE', '/sessions/$sessionId');

    if (response.statusCode != 200) {
      print('❌ Failed to delete session: ${response.statusCode}');
      throw Exception('Failed to delete session: ${response.body}');
    }
    print('✅ Session deleted successfully');
  }

  // Batch endpoints
  static Future<List<Batch>> getAllBatches() async {
    print('📦 Fetching all batches...');
    final response = await _makeRequest('GET', '/batches');

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      print('✅ Retrieved ${data.length} batches');
      return data.map((json) => Batch.fromJson(json)).toList();
    } else {
      print('❌ Failed to fetch batches: ${response.statusCode}');
      throw Exception('Failed to fetch batches: ${response.body}');
    }
  }

  static Future<Batch> createBatch(Map<String, dynamic> batchData) async {
    print('📦 Creating new batch...');
    final response = await _makeRequest(
      'POST',
      '/batches',
      body: batchData,
    );

    if (response.statusCode == 201) {
      print('✅ Batch created successfully');
      return Batch.fromJson(jsonDecode(response.body));
    } else {
      print('❌ Failed to create batch: ${response.statusCode}');
      throw Exception('Failed to create batch: ${response.body}');
    }
  }

  static Future<Batch> getBatchById(String batchId) async {
    print('📦 Fetching batch: $batchId');
    final response = await _makeRequest('GET', '/batches/$batchId');

    if (response.statusCode == 200) {
      print('✅ Batch retrieved successfully');
      return Batch.fromJson(jsonDecode(response.body));
    } else {
      print('❌ Failed to fetch batch: ${response.statusCode}');
      throw Exception('Failed to fetch batch: ${response.body}');
    }
  }

  static Future<Batch> updateBatch(
      String batchId, Map<String, dynamic> batchData) async {
    print('✏️ Updating batch: $batchId');
    final response = await _makeRequest(
      'PUT',
      '/batches/$batchId',
      body: batchData,
    );

    if (response.statusCode == 200) {
      print('✅ Batch updated successfully');
      return Batch.fromJson(jsonDecode(response.body));
    } else {
      print('❌ Failed to update batch: ${response.statusCode}');
      throw Exception('Failed to update batch: ${response.body}');
    }
  }

  static Future<void> deleteBatch(String batchId) async {
    print('🗑️ Deleting batch: $batchId');
    final response = await _makeRequest('DELETE', '/batches/$batchId');

    if (response.statusCode != 200) {
      print('❌ Failed to delete batch: ${response.statusCode}');
      throw Exception('Failed to delete batch: ${response.body}');
    }
    print('✅ Batch deleted successfully');
  }

  // Image upload endpoint
  static Future<String> uploadImage(File imageFile, String sessionId) async {
    print('📸 Uploading image for session: $sessionId');
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

      print('📤 Sending multipart request...');
      final streamedResponse = await request.send().timeout(ApiConfig.timeout);
      final response = await http.Response.fromStream(streamedResponse);

      print('📥 Upload response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ Image uploaded successfully: ${data['imageUrl']}');
        return data['imageUrl'];
      } else {
        print('❌ Failed to upload image: ${response.body}');
        throw Exception('Failed to upload image: ${response.body}');
      }
    } catch (e) {
      print('❌ Image upload failed: $e');
      throw Exception('Image upload failed: $e');
    }
  }

  // User endpoints
  static Future<User> getCurrentUser() async {
    print('👤 Fetching current user...');
    final response = await _makeRequest('GET', '/user/me');

    if (response.statusCode == 200) {
      print('✅ User data retrieved successfully');
      return User.fromJson(jsonDecode(response.body));
    } else {
      print('❌ Failed to fetch user: ${response.statusCode}');
      throw Exception('Failed to fetch user: ${response.body}');
    }
  }

  static Future<User> updateUser(
      String userId, Map<String, dynamic> userData) async {
    print('✏️ Updating user: $userId');
    final response = await _makeRequest(
      'PUT',
      '/user/$userId',
      body: userData,
    );

    if (response.statusCode == 200) {
      print('✅ User updated successfully');
      return User.fromJson(jsonDecode(response.body));
    } else {
      print('❌ Failed to update user: ${response.statusCode}');
      throw Exception('Failed to update user: ${response.body}');
    }
  }

  // Sync local data with server
  static Future<void> syncLocalData(List<Session> localSessions) async {
    print('🔄 Syncing ${localSessions.length} local sessions...');
    try {
      final response = await _makeRequest(
        'POST',
        '/sync',
        body: {
          'sessions': localSessions.map((s) => s.toJson()).toList(),
        },
      );

      if (response.statusCode != 200) {
        print('❌ Failed to sync data: ${response.statusCode}');
        throw Exception('Failed to sync data: ${response.body}');
      }
      print('✅ Data synced successfully');
    } catch (e) {
      print('❌ Data sync failed: $e');
      throw Exception('Data sync failed: $e');
    }
  }

  // Health check
  static Future<bool> checkConnection() async {
    print('🏥 Checking API connection...');
    try {
      final response = await _makeRequest(
        'GET',
        '/health',
        requiresAuth: false,
      );
      final isHealthy = response.statusCode == 200;
      print(isHealthy ? '✅ API is healthy' : '❌ API health check failed');
      return isHealthy;
    } catch (e) {
      print('❌ Connection check failed: $e');
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
    print('💾 Token saved');
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    print('🗑️ Token cleared');
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> saveUserData(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(userData));
    print('💾 User data saved');
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
