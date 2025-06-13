import 'package:hive/hive.dart';

part 'session_model.g.dart';

@HiveType(typeId: 0)
class SessionModel extends HiveObject {
  @HiveField(0)
  final String batchId;

  @HiveField(1)
  final String species;

  @HiveField(2)
  final String location;

  @HiveField(3)
  final String notes;

  @HiveField(4)
  final DateTime date;

  @HiveField(5)
  final int count;

  SessionModel({
    required this.batchId,
    required this.species,
    required this.location,
    this.notes = '',
    required this.date,
    required this.count,
  });
} 