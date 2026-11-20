// models/task.dart
class Task {
  final int id;
  final String title;
  final String? description;
  final int createdBy;
  final List<int> assignedTo;
  final List<int> supervisorId;
  final String priority;
  final String status;
  final String? image;
  final String? dueDate;
  final String? completedAt;
  final String frequencyType;
  final int? frequencyValue;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? remarks;

  Task({
    required this.id,
    required this.title,
    this.description,
    required this.createdBy,
    this.assignedTo = const [],
    this.supervisorId = const [],
    required this.priority,
    required this.status,
    this.image,
    this.dueDate,
    this.remarks,
    this.completedAt,
    required this.frequencyType,
    this.frequencyValue,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: _parseInt(json['id']) ?? 0,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      createdBy: _parseInt(json['created_by']) ?? 0,
      assignedTo: _parseIntList(json['assigned_to']),
      supervisorId: _parseIntList(json['supervisor_id']),
      priority: json['priority'] as String? ?? 'normal',
      status: json['status'] as String? ?? 'pending',
      image: json['image'] as String?,
      dueDate: _parseNullableDateString(json['due_date']),
      remarks: json['remarks'] as String?, // Add this
      completedAt: json['completed_at']?.toString(),
      frequencyType: json['frequency_type'] as String? ?? 'none',
      frequencyValue: _parseInt(json['frequency_value']),
      createdAt: _parseDateTime(json['created_at'] ?? json['createdAt']),
      updatedAt: _parseDateTime(json['updated_at'] ?? json['updatedAt']),
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) {
      if (value.isEmpty) return null;
      return int.tryParse(value);
    }
    if (value is double) return value.toInt();
    return null;
  }

  static List<int> _parseIntList(dynamic value) {
    if (value == null) return [];
    if (value is int) return [value];
    if (value is List) {
      return value.map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0).toList();
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      return parsed != null ? [parsed] : [];
    }
    return [];
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return DateTime.now();
      }
    }
    if (value is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(value);
      } catch (e) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }

  static String? _parseNullableDateString(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return null;
    return s;
  }

  String get formattedStatus {
    switch (status) {
      case 'pending': return 'Хүлээгдэж байна';
      case 'in_progress': return 'Хийгдэж байна';
      case 'done': return 'Дууссан';
      case 'verified': return 'Баталгаажсан';
      case 'cancelled': return 'Цуцлагдсан';
      default: return status;
    }
  }

  String get formattedPriority {
    switch (priority) {
      case 'high': return 'Өндөр';
      case 'normal': return 'Хэвийн';
      case 'low': return 'Бага';
      default: return priority;
    }
  }

  String get formattedFrequency {
    switch (frequencyType) {
      case 'daily': return 'Өдөр бүр';
      case 'weekly': return 'Долоо хоног бүр';
      case 'monthly': return 'Сар бүр';
      case 'none': return 'Нэг удаа';
      default: return frequencyType;
    }
  }

  DateTime? get parsedDueDate => _parseOptionalDateTime(dueDate);

  DateTime? get parsedCompletedAt => _parseOptionalDateTime(completedAt);

  /// End of the due calendar day (deadline).
  static DateTime? dueEndOfDay(String? dueDateStr) {
    final due = _parseOptionalDateTimeStatic(dueDateStr);
    if (due == null) return null;
    return DateTime(due.year, due.month, due.day, 23, 59, 59);
  }

  /// Pending/in_progress task past its due date.
  bool get isOverdue {
    if (status != 'pending' && status != 'in_progress') return false;
    final dueEnd = dueEndOfDay(dueDate);
    if (dueEnd == null) return false;
    return DateTime.now().isAfter(dueEnd);
  }

  /// Completed after the due date (uses completed_at, falls back to updatedAt).
  bool get wasCompletedLate {
    if (status != 'done' && status != 'verified') return false;
    final dueEnd = dueEndOfDay(dueDate);
    if (dueEnd == null) return false;
    final completed = parsedCompletedAt ?? updatedAt;
    return completed.isAfter(dueEnd);
  }

  bool get wasCompletedOnTime {
    if (status != 'done' && status != 'verified') return false;
    if (dueDate == null) return false;
    return !wasCompletedLate;
  }

  /// Mongolian label for timeliness (null if not applicable).
  String? get timelinessLabel {
    if (isOverdue) return 'Хугацаа хэтэрсэн';
    if (wasCompletedLate) return 'Хугацаа хэтэрч дууссан';
    if (wasCompletedOnTime) return 'Цагтаа дууссан';
    return null;
  }

  static bool checkIsOverdue(String status, String? dueDateStr) {
    if (status != 'pending' && status != 'in_progress') return false;
    final dueEnd = dueEndOfDay(dueDateStr);
    if (dueEnd == null) return false;
    return DateTime.now().isAfter(dueEnd);
  }

  static bool checkWasCompletedLate(
    String status,
    String? dueDateStr,
    String? completedAtStr,
    DateTime? fallbackCompletedAt,
  ) {
    if (status != 'done' && status != 'verified') return false;
    final dueEnd = dueEndOfDay(dueDateStr);
    if (dueEnd == null) return false;
    final completed =
        _parseOptionalDateTimeStatic(completedAtStr) ?? fallbackCompletedAt;
    if (completed == null) return false;
    return completed.isAfter(dueEnd);
  }

  static DateTime? _parseOptionalDateTimeStatic(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      final s = value.trim();
      if (s.isEmpty || s.toLowerCase() == 'null') return null;
      try {
        return DateTime.parse(s);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  DateTime? _parseOptionalDateTime(dynamic value) =>
      _parseOptionalDateTimeStatic(value);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'created_by': createdBy,
      'assigned_to': assignedTo,
      'supervisor_id': supervisorId,
      'priority': priority,
      'status': status,
      'image': image,
      'due_date': dueDate,
      'remarks': remarks, // Add this
      'completed_at': completedAt,
      'frequency_type': frequencyType,
      'frequency_value': frequencyValue,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}