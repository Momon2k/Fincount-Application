class Session {
  final String id;
  final String batchId;
  final String species;
  final String location;
  final String notes;
  final Map<String, int> counts;
  final String timestamp;
  final String imageUrl;
  final String? userId; // ✅ Add userId field

  Session({
    required this.id,
    required this.batchId,
    required this.species,
    required this.location,
    required this.notes,
    required this.counts,
    required this.timestamp,
    required this.imageUrl,
    this.userId, // ✅ Optional userId
  });

  /// Normalize species name to match backend requirements
  /// Backend expects: "Tilapia" or "Bangus (Milkfish)"
  String _normalizeSpecies(String species) {
    final speciesLower = species.toLowerCase().trim();
    
    if (speciesLower.contains('tilapia')) {
      return 'Tilapia';
    } else if (speciesLower.contains('bangus') || speciesLower.contains('milkfish')) {
      return 'Bangus (Milkfish)';
    }
    
    // Return as-is if no match (backend will validate)
    return species;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'batchId': batchId,
      'species': _normalizeSpecies(species), // Normalize species for API
      'location': location,
      'notes': notes,
      'counts': counts,
      'timestamp': timestamp,
      'imageUrl': imageUrl,
      if (userId != null) 'userId': userId, // ✅ Include userId if available
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
      userId: json['userId'], // ✅ Parse userId from JSON
    );
  }
}
