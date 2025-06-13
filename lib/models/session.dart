import 'package:flutter/foundation.dart';

class Session {
  final String id;
  final String batchId;
  final String species;
  final String location;
  final String notes;
  final Map<String, int> counts;
  final String timestamp;
  final String imageUrl;

  Session({
    required this.id,
    required this.batchId,
    required this.species,
    required this.location,
    required this.notes,
    required this.counts,
    required this.timestamp,
    required this.imageUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'batchId': batchId,
      'species': species,
      'location': location,
      'notes': notes,
      'counts': counts,
      'timestamp': timestamp,
      'imageUrl': imageUrl,
    };
  }

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'],
      batchId: json['batchId'],
      species: json['species'],
      location: json['location'],
      notes: json['notes'],
      counts: Map<String, int>.from(json['counts']),
      timestamp: json['timestamp'],
      imageUrl: json['imageUrl'],
    );
  }
} 