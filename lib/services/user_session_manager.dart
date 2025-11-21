import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/session_model.dart';
import 'api_service.dart';

/// Manages user-specific storage and ensures data isolation between users
class UserSessionManager {
  static String? _currentUserId;
  static Box<SessionModel>? _currentUserBox;

  /// Initialize user session with their specific storage
  static Future<void> initializeUserSession(String userId) async {
    print('🔐 Initializing user session for: $userId');
    _currentUserId = userId;
    
    // Close any existing box first
    if (_currentUserBox != null && _currentUserBox!.isOpen) {
      await _currentUserBox!.close();
      print('📦 Closed previous user box');
    }
    
    // Open user-specific Hive box
    final boxName = getUserBoxName();
    try {
      _currentUserBox = await Hive.openBox<SessionModel>(boxName);
      print('✅ Opened user-specific box: $boxName');
    } catch (e) {
      print('❌ Error opening user box: $e');
      rethrow;
    }
  }

  /// Clear current user session (call on logout)
  static Future<void> clearUserSession() async {
    print('🚪 Clearing user session');
    
    if (_currentUserBox != null && _currentUserBox!.isOpen) {
      await _currentUserBox!.close();
      print('📦 Closed user box');
    }
    
    _currentUserId = null;
    _currentUserBox = null;
    print('✅ User session cleared');
  }

  /// Get current user ID
  static String getCurrentUserId() {
    if (_currentUserId == null) {
      throw Exception('No user logged in. User ID not available.');
    }
    return _currentUserId!;
  }

  /// Get current user's Hive box
  static Box<SessionModel> getCurrentUserBox() {
    if (_currentUserBox == null || !_currentUserBox!.isOpen) {
      throw Exception('User box not initialized. Please login first.');
    }
    return _currentUserBox!;
  }

  /// Check if user is logged in
  static bool isUserLoggedIn() {
    return _currentUserId != null && 
           _currentUserBox != null && 
           _currentUserBox!.isOpen;
  }

  /// Get user-specific box name
  static String getUserBoxName() {
    if (_currentUserId == null) {
      throw Exception('No user logged in. Cannot generate box name.');
    }
    return 'sessions_$_currentUserId';
  }

  /// Get user-specific SharedPreferences key
  static String getUserKey(String baseKey) {
    if (_currentUserId == null) {
      throw Exception('No user logged in. Cannot generate user key.');
    }
    return '${baseKey}_$_currentUserId';
  }

  /// Load stored user ID from SharedPreferences
  static Future<String?> loadStoredUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  /// Initialize session from stored user ID (for app restart)
  static Future<bool> initializeFromStoredSession() async {
    print('🔄 Attempting to restore user session...');
    
    final userId = await loadStoredUserId();
    if (userId != null && userId.isNotEmpty) {
      final isLoggedIn = await AuthService.isLoggedIn();
      if (isLoggedIn) {
        await initializeUserSession(userId);
        print('✅ User session restored: $userId');
        return true;
      }
    }
    
    print('❌ No stored session found');
    return false;
  }

  /// Delete all data for a specific user (for account deletion)
  static Future<void> deleteUserData(String userId) async {
    print('🗑️ Deleting all data for user: $userId');
    
    // Close box if it's the current user
    if (_currentUserId == userId && _currentUserBox != null) {
      await _currentUserBox!.close();
    }
    
    // Delete Hive box
    final boxName = 'sessions_$userId';
    try {
      await Hive.deleteBoxFromDisk(boxName);
      print('✅ Deleted Hive box: $boxName');
    } catch (e) {
      print('⚠️ Could not delete Hive box: $e');
    }
    
    // Delete SharedPreferences keys
    final prefs = await SharedPreferences.getInstance();
    final keysToDelete = [
      'sessions_$userId',
      'batches_$userId',
      'synced_sessions_$userId',
      'sync_status_$userId',
      'last_sync_$userId',
    ];
    
    for (final key in keysToDelete) {
      await prefs.remove(key);
    }
    
    print('✅ Deleted SharedPreferences for user: $userId');
  }

  /// Get all available user IDs (for debugging/admin purposes)
  static Future<List<String>> getAllUserIds() async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();
    
    final userIds = <String>{};
    for (final key in allKeys) {
      if (key.startsWith('sessions_') || key.startsWith('batches_')) {
        final userId = key.split('_').last;
        userIds.add(userId);
      }
    }
    
    return userIds.toList();
  }
}
