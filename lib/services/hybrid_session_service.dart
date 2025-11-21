import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/session.dart';
import 'api_service.dart';
import 'session_service.dart';

/// Hybrid service that handles both local and remote data storage
/// Falls back to local storage when API is unavailable
class HybridSessionService {
  static const String _syncStatusKey = 'sync_status';
  static const String _lastSyncKey = 'last_sync';

  final SessionService _localService = SessionService();

  /// Save session with automatic sync attempt - ERROR HANDLING REMOVED FOR DEBUGGING
  /// Returns a map with sync status information
  Future<Map<String, dynamic>> saveSession(Session session) async {
    print('=== Starting saveSession ===');
    print('Session ID: ${session.id}');
    print('Batch ID: ${session.batchId}');

    bool savedLocally = false;
    bool syncedToApi = false;
    String? syncError;

    // Always save locally first - NO ERROR HANDLING
    print('Attempting to save session locally...');
    await _localService.saveSession(session);
    savedLocally = true;
    print('✓ Session saved locally');

    // Try to sync with API - NO ERROR HANDLING
    print('Checking connection...');
    final isConnected = await ApiService.checkConnection();
    print('Connection status: $isConnected');

    if (isConnected) {
      print('Attempting to create session on API...');
      final result = await ApiService.createSession(session);
      print('✓ Session created on API: $result');
      await _markAsSynced(session.id);
      syncedToApi = true;
      print('✓ Session marked as synced');
    } else {
      print('⚠ Device is offline, marking as unsynced');
      await _markAsUnsynced(session.id);
      syncError = 'No internet connection';
    }

    return {
      'savedLocally': savedLocally,
      'syncedToApi': syncedToApi,
      'syncError': syncError,
    };
  }

  /// Get all sessions (prioritize API if available, fallback to local) - ERROR HANDLING REMOVED
  Future<List<Session>> getAllSessions() async {
    print('=== Getting all sessions ===');
    final isConnected = await ApiService.checkConnection();
    print('Connection status: $isConnected');
    
    if (isConnected) {
      print('Fetching sessions from API...');
      final apiSessions = await ApiService.getAllSessions();
      print('API sessions fetched: ${apiSessions.length}');
      // Update local storage with API data
      await _updateLocalFromApi(apiSessions);
      return apiSessions;
    }

    // Fallback to local data
    print('Using local data...');
    return await _localService.getAllSessions();
  }

  /// Get sessions for a specific batch - ERROR HANDLING REMOVED
  Future<List<Session>> getBatchSessions(String batchId) async {
    print('=== Getting batch sessions for: $batchId ===');
    final isConnected = await ApiService.checkConnection();
    print('Connection status: $isConnected');
    
    if (isConnected) {
      print('Fetching batch sessions from API...');
      return await ApiService.getBatchSessions(batchId);
    }

    // Fallback to local data
    print('Using local data...');
    return await _localService.getBatchSessions(batchId);
  }

  /// Get all batches - ERROR HANDLING REMOVED
  Future<dynamic> getAllBatches() async {
    print('=== Getting all batches ===');
    final isConnected = await ApiService.checkConnection();
    print('Connection status: $isConnected');
    
    if (isConnected) {
      print('Fetching batches from API...');
      // API now returns List<Batch>
      return await ApiService.getAllBatches();
    }

    // Fallback to local data (returns Map<String, dynamic>)
    print('Using local data...');
    return await _localService.getAllBatches();
  }

  /// Sync all local data with the API - ERROR HANDLING REMOVED
  Future<bool> syncAllData() async {
    print('=== Syncing all data ===');
    final isConnected = await ApiService.checkConnection();
    print('Connection status: $isConnected');
    
    if (!isConnected) {
      print('No connection, aborting sync');
      return false;
    }

    // Get all local sessions
    print('Getting local sessions...');
    final localSessions = await _localService.getAllSessions();
    print('Local sessions count: ${localSessions.length}');
    
    final unsyncedSessions = await _getUnsyncedSessions(localSessions);
    print('Unsynced sessions count: ${unsyncedSessions.length}');

    if (unsyncedSessions.isNotEmpty) {
      // Sync unsynced sessions - NO ERROR HANDLING
      for (final session in unsyncedSessions) {
        print('Syncing session: ${session.id}');
        await ApiService.createSession(session);
        await _markAsSynced(session.id);
        print('Session synced: ${session.id}');
      }
    }

    // Get latest data from API and update local storage
    print('Fetching latest data from API...');
    final apiSessions = await ApiService.getAllSessions();
    print('API sessions fetched: ${apiSessions.length}');
    
    await _updateLocalFromApi(apiSessions);
    print('Local storage updated');

    await _updateLastSyncTime();
    print('Last sync time updated');
    print('=== Sync completed successfully ===');
    return true;
  }

  /// Check if device is online and can connect to API
  Future<bool> isOnline() async {
    return await ApiService.checkConnection();
  }

  /// Get sync status information
  Future<Map<String, dynamic>> getSyncStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString(_lastSyncKey);
    final localSessions = await _localService.getAllSessions();
    final unsyncedSessions = await _getUnsyncedSessions(localSessions);

    return {
      'lastSync': lastSync,
      'totalSessions': localSessions.length,
      'unsyncedSessions': unsyncedSessions.length,
      'isOnline': await isOnline(),
    };
  }

  /// Force refresh from API (useful for manual refresh)
  Future<List<Session>> refreshFromApi() async {
    final apiSessions = await ApiService.getAllSessions();
    await _updateLocalFromApi(apiSessions);
    return apiSessions;
  }

  // Private helper methods

  Future<void> _markAsSynced(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final syncedIds = prefs.getStringList('synced_sessions') ?? [];
    if (!syncedIds.contains(sessionId)) {
      syncedIds.add(sessionId);
      await prefs.setStringList('synced_sessions', syncedIds);
    }
  }

  Future<void> _markAsUnsynced(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final syncedIds = prefs.getStringList('synced_sessions') ?? [];
    syncedIds.remove(sessionId);
    await prefs.setStringList('synced_sessions', syncedIds);
  }

  Future<List<Session>> _getUnsyncedSessions(List<Session> allSessions) async {
    final prefs = await SharedPreferences.getInstance();
    final syncedIds = prefs.getStringList('synced_sessions') ?? [];
    return allSessions
        .where((session) => !syncedIds.contains(session.id))
        .toList();
  }

  Future<void> _updateLocalFromApi(List<Session> apiSessions) async {
    // This is a simplified approach - in production you might want more sophisticated merging
    final prefs = await SharedPreferences.getInstance();
    final sessionStrings =
        apiSessions.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList('sessions', sessionStrings);

    // Mark all API sessions as synced
    final syncedIds = apiSessions.map((s) => s.id).toList();
    await prefs.setStringList('synced_sessions', syncedIds);
  }

  Future<void> _updateLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
  }
}
