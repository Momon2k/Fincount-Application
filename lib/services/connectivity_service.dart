import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'hybrid_session_service.dart';

/// Service that monitors network connectivity and automatically syncs data
/// when the device transitions from offline to online
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  final HybridSessionService _hybridService = HybridSessionService();
  
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _wasOffline = false;
  bool _isInitialized = false;
  bool _isSyncing = false;
  
  // Callback for sync completion notifications
  Function(bool success, String? message)? onSyncComplete;

  /// Initialize connectivity monitoring
  Future<void> initialize() async {
    if (_isInitialized) {
      print('ConnectivityService already initialized');
      return;
    }

    print('=== Initializing ConnectivityService ===');
    
    // Check initial connectivity status
    final connectivityResult = await _connectivity.checkConnectivity();
    _wasOffline = !_isConnected(connectivityResult);
    print('Initial connectivity status: ${_wasOffline ? "Offline" : "Online"}');

    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
      onError: (error) {
        print('Connectivity stream error: $error');
      },
    );

    _isInitialized = true;
    print('ConnectivityService initialized successfully');
  }

  /// Handle connectivity changes
  void _onConnectivityChanged(List<ConnectivityResult> results) async {
    final isOnline = _isConnected(results);
    print('=== Connectivity changed: ${isOnline ? "Online" : "Offline"} ===');

    // Detect offline → online transition
    if (_wasOffline && isOnline) {
      print('📡 Device came back online - triggering auto-sync');
      await _performAutoSync();
    }

    _wasOffline = !isOnline;
  }

  /// Check if device is connected based on connectivity results
  bool _isConnected(List<ConnectivityResult> results) {
    return results.any((result) =>
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet);
  }

  /// Perform automatic sync when connection is restored
  Future<void> _performAutoSync() async {
    if (_isSyncing) {
      print('Sync already in progress, skipping...');
      return;
    }

    _isSyncing = true;
    print('Starting automatic sync...');

    try {
      // Small delay to ensure connection is stable
      await Future.delayed(const Duration(seconds: 2));

      // Check sync status before syncing
      final syncStatus = await _hybridService.getSyncStatus();
      final unsyncedCount = syncStatus['unsyncedSessions'] as int;

      print('Unsynced sessions count: $unsyncedCount');

      if (unsyncedCount > 0) {
        print('Syncing $unsyncedCount unsynced sessions...');
        final success = await _hybridService.syncAllData();
        
        if (success) {
          print('✅ Auto-sync completed successfully');
          _notifySyncComplete(true, 'Synced $unsyncedCount session(s) successfully');
        } else {
          print('⚠️ Auto-sync failed');
          _notifySyncComplete(false, 'Failed to sync data');
        }
      } else {
        print('No unsynced data - skipping sync');
        _notifySyncComplete(true, 'All data is already synced');
      }
    } catch (e) {
      print('❌ Auto-sync error: $e');
      _notifySyncComplete(false, 'Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Notify listeners about sync completion
  void _notifySyncComplete(bool success, String? message) {
    if (onSyncComplete != null) {
      try {
        onSyncComplete!(success, message);
      } catch (e) {
        print('Error in sync completion callback: $e');
      }
    }
  }

  /// Force trigger auto-sync check (useful after login or manual trigger)
  Future<void> checkAndSync() async {
    final isOnline = await this.isOnline();
    
    if (isOnline) {
      print('Manual sync check - device is online, triggering sync...');
      await _performAutoSync();
    } else {
      print('Manual sync check - device is offline, skipping sync');
    }
  }

  /// Manually trigger a sync (can be called from UI)
  Future<bool> manualSync() async {
    print('Manual sync triggered');
    await _performAutoSync();
    return !_isSyncing;
  }

  /// Get current connectivity status
  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return _isConnected(results);
  }

  /// Dispose and clean up resources
  void dispose() {
    print('Disposing ConnectivityService');
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _isInitialized = false;
  }

  /// Get initialization status
  bool get isInitialized => _isInitialized;

  /// Get syncing status
  bool get isSyncing => _isSyncing;
}
