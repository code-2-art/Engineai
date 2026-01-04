import 'dart:typed_data';

enum TaskType { chat, image }
enum TaskStatus { pending, running, paused, completed, failed, cancelled }

class GenerationTask {
  final String id;
  final TaskType type;
  final TaskStatus status;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String sessionId;
  final Map<String, dynamic> params;
  String? currentResponse;
  Uint8List? generatedImage;
  String? error;

  GenerationTask({
    required this.id,
    required this.type,
    required this.status,
    required this.createdAt,
    this.completedAt,
    required this.sessionId,
    required this.params,
    this.currentResponse,
    this.generatedImage,
    this.error,
  });

  GenerationTask copyWith({
    TaskType? type,
    TaskStatus? status,
    DateTime? completedAt,
    String? currentResponse,
    Uint8List? generatedImage,
    String? error,
  }) {
    return GenerationTask(
      id: id,
      type: type ?? this.type,
      status: status ?? this.status,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
      sessionId: sessionId,
      params: params,
      currentResponse: currentResponse ?? this.currentResponse,
      generatedImage: generatedImage ?? this.generatedImage,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'sessionId': sessionId,
      'params': params,
      'currentResponse': currentResponse,
      'error': error,
    };
  }

  factory GenerationTask.fromJson(Map<String, dynamic> json) {
    return GenerationTask(
      id: json['id'] as String,
      type: TaskType.values.firstWhere((e) => e.name == json['type']),
      status: TaskStatus.values.firstWhere((e) => e.name == json['status']),
      createdAt: DateTime.parse(json['createdAt'] as String),
      completedAt: json['completedAt'] != null 
          ? DateTime.parse(json['completedAt'] as String) 
          : null,
      sessionId: json['sessionId'] as String,
      params: json['params'] as Map<String, dynamic>,
      currentResponse: json['currentResponse'] as String?,
      error: json['error'] as String?,
    );
  }
}
