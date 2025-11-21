import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/session.dart';

class SessionService {
  static const String _sessionsKey = 'sessions';
  static const String _batchesKey = 'batches';

  // Save a new session - WITH ERROR LOGGING
  Future<void> saveSession(Session session) async {
    print('=== SESSION SAVE STARTED ===');
    print('Session Data: ${jsonEncode(session.toJson())}');
    
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    print('SharedPreferences instance obtained');
    
    // Get existing sessions
    List<String> sessions = prefs.getStringList(_sessionsKey) ?? [];
    print('Existing sessions count: ${sessions.length}');
    
    sessions.add(jsonEncode(session.toJson()));
    print('Session added to list. New count: ${sessions.length}');
    
    await prefs.setStringList(_sessionsKey, sessions);
    print('Sessions saved to SharedPreferences');

    // Update batch information
    Map<String, dynamic> batches = jsonDecode(prefs.getString(_batchesKey) ?? '{}');
    print('Existing batches: ${batches.keys.toList()}');
    
    if (!batches.containsKey(session.batchId)) {
      print('Creating new batch: ${session.batchId}');
      batches[session.batchId] = {
        'species': session.species,
        'location': session.location,
        'notes': session.notes,
        'lastUpdate': session.timestamp,
        'totalCounts': session.counts,
      };
    } else {
      print('Updating existing batch: ${session.batchId}');
      // Update existing batch counts
      Map<String, dynamic> batch = batches[session.batchId];
      Map<String, int> totalCounts = Map<String, int>.from(batch['totalCounts'] ?? {});
      print('Current total counts: $totalCounts');
      
      session.counts.forEach((key, value) {
        totalCounts[key] = (totalCounts[key] ?? 0) + value;
      });
      print('Updated total counts: $totalCounts');
      
      batch['totalCounts'] = totalCounts;
      batch['lastUpdate'] = session.timestamp;
      batches[session.batchId] = batch;
    }
    
    await prefs.setString(_batchesKey, jsonEncode(batches));
    print('Batches saved to SharedPreferences');
    print('=== SESSION SAVE COMPLETED SUCCESSFULLY ===');
  }

  // Get all sessions
  Future<List<Session>> getAllSessions() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final sessions = prefs.getStringList(_sessionsKey) ?? [];
    return sessions
        .map((s) => Session.fromJson(jsonDecode(s)))
        .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  // Get sessions for a specific batch
  Future<List<Session>> getBatchSessions(String batchId) async {
    final sessions = await getAllSessions();
    return sessions.where((s) => s.batchId == batchId).toList();
  }

  // Get all batches
  Future<Map<String, dynamic>> getAllBatches() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String batchesJson = prefs.getString(_batchesKey) ?? '{}';
    return jsonDecode(batchesJson);
  }
}
