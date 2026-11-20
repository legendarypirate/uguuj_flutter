// recurring_tasks_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'color/color.dart';
import 'models/task.dart';
import 'login.dart' as auth;

class RecurringTasksScreen extends StatefulWidget {
  @override
  _RecurringTasksScreenState createState() => _RecurringTasksScreenState();
}

class _RecurringTasksScreenState extends State<RecurringTasksScreen> {
  List<Task> _allRecurringTasks = [];
  List<Task> _filteredTasks = [];
  DateTime? _rangeStartDate;
  DateTime? _rangeEndDate;
  bool _isLoading = true;
  int? _currentUserId;
  String? _userName;
  String? _userRole;
  String? _selectedPriority;
  String? _selectedStatus;
  final ImagePicker _picker = ImagePicker();

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    if (value is double) return value.toInt();
    return null;
  }

  List<int> _toIntList(dynamic value) {
    if (value == null) return [];
    if (value is int) return [value];
    if (value is List) {
      return value.map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0).toList();
    }
    return [];
  }

  DateTime? _safeParseDate(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  DateTime _normalizeDate(DateTime date) => DateTime(date.year, date.month, date.day);

  // Modern color palette
  final Map<String, Color> _statusColors = {
    'pending': Color(0xFFFF6B35),
    'in_progress': Color(0xFF4ECDC4),
    'done': Color(0xFF06D6A0),
    'verified': Color(0xFF9D4EDD),
    'cancelled': Color(0xFFEF476F),
  };

  final Map<String, Color> _priorityColors = {
    'high': Color(0xFFEF476F),
    'normal': Color(0xFFFFD166),
    'low': Color(0xFF06D6A0),
  };

  @override
  void initState() {
    super.initState();
    _loadUserAndTasks();
  }

  Future<void> _loadUserAndTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('userId');
      final userName = prefs.getString('userName');
      final userRole = prefs.getString('role');

      if (userId == null) {
        _showErrorSnackBar('Хэрэглэгч нэвтрээгүй байна');
        return;
      }

      setState(() {
        _currentUserId = userId;
        _userName = userName;
        _userRole = userRole;
      });

      await _fetchTasks();
    } catch (e) {
      print('❌ Error loading user data: $e');
      _showErrorSnackBar('Хэрэглэгчийн мэдээлэл ачааллахад алдаа гарлаа');
    }
  }

  Future<void> _fetchTasks() async {
    if (_currentUserId == null) {
      _showErrorSnackBar('Хэрэглэгч нэвтрээгүй байна');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      print('🔄 Fetching recurring tasks for user ID: $_currentUserId, Role: $_userRole');
      final response = await http.get(Uri.parse(Url.url + '/api/task'));

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        final List<dynamic> tasksJson = jsonData['data'] ?? [];

        List<dynamic> userTasks = [];

        // Check if user is director or general_manager
        if (_userRole == 'director' || _userRole == 'general_manager') {
          userTasks = tasksJson;
        } else if (_userRole == 'supervisor') {
          // Supervisor visibility:
          // - directly assigned to supervisor
          // - legacy supervisor_id match
          // - tasks assigned to this supervisor's subordinate workers
          Set<int> subordinateIds = {};
          try {
            final allWorkers = await auth.AuthService.getWorkers();
            subordinateIds = allWorkers
                .where((w) =>
                    w.role.toLowerCase() == 'worker' &&
                    w.supervisor_id.contains(_currentUserId))
                .map((w) => w.id)
                .toSet();
            print('👥 Recurring supervisor subordinate worker IDs: $subordinateIds');
          } catch (e) {
            print('⚠️ Could not load subordinates for recurring visibility: $e');
          }

          userTasks = tasksJson.where((taskJson) {
            final assignedToList = _toIntList(taskJson['assigned_to']);
            final supervisorIdList = _toIntList(taskJson['supervisor_id']);
            final uid = _currentUserId;
            return assignedToList.contains(uid) ||
                supervisorIdList.contains(uid) ||
                assignedToList.any((id) => subordinateIds.contains(id));
          }).toList();
        } else {
          userTasks = tasksJson.where((taskJson) {
            final assignedToList = _toIntList(taskJson['assigned_to']);
            return assignedToList.contains(_currentUserId);
          }).toList();
        }

        // Давтамжит загварууд л (нэг удаагийн due_date-тай ажил TaskList дээр үлдэнэ).
        final recurringTasks = userTasks.where((taskJson) {
          final frequencyType = taskJson['frequency_type']?.toString();
          final frequencyValue = taskJson['frequency_value'];
          return frequencyType != null &&
              frequencyType != 'none' &&
              frequencyType.isNotEmpty &&
              frequencyValue != null;
        }).toList();

        print('✅ Loaded ${recurringTasks.length} recurring tasks');

        setState(() {
          _allRecurringTasks = recurringTasks.map((taskJson) => Task.fromJson(taskJson)).toList();
          _filterTasksByRange(startDate: _rangeStartDate, endDate: _rangeEndDate);
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load tasks: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching tasks: $e');
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Даалгавруудыг ачааллахад алдаа гарлаа: $e');
    }
  }

  bool _isTaskDueInRange(
    DateTime baseDate,
    DateTime rangeStart,
    DateTime rangeEnd,
    String frequencyType,
    int? frequencyValue,
  ) {
    DateTime cursor = _normalizeDate(rangeStart);
    final end = _normalizeDate(rangeEnd);
    while (!cursor.isAfter(end)) {
      if (_isTaskDueOnDate(baseDate, cursor, frequencyType, frequencyValue)) {
        return true;
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return false;
  }

  void _filterTasksByRange({DateTime? startDate, DateTime? endDate}) {
    setState(() {
      _rangeStartDate = startDate;
      _rangeEndDate = endDate;

      final hasRange = _rangeStartDate != null;
      if (!hasRange) {
        _filteredTasks = _allRecurringTasks;
      } else {
        final rangeStart = _normalizeDate(_rangeStartDate!);
        final rangeEnd = _normalizeDate(_rangeEndDate ?? _rangeStartDate!);

        // Filter tasks that should occur in selected date range
        _filteredTasks = _allRecurringTasks.where((task) {
          final frequencyType = task.frequencyType;
          final frequencyValue = task.frequencyValue;

          if (frequencyValue == null) return false;
          if (frequencyType == 'none' || frequencyType.isEmpty) return false;
          
          // For monthly tasks, if dueDate is null, use createdAt as base date
          // For other frequency types, dueDate is required
          DateTime? baseDate;
          if (task.dueDate != null) {
            baseDate = _safeParseDate(task.dueDate);
          } else if (frequencyType == 'monthly' ||
              frequencyType == 'daily' ||
              frequencyType == 'weekly') {
            // Recurring jobs from admin often have null due_date; use creation date.
            final c = task.createdAt;
            baseDate = DateTime(c.year, c.month, c.day);
          } else {
            return false;
          }

          if (baseDate == null) return false;
          
          // Check if recurring pattern matches at least one date in selected range.
          return _isTaskDueInRange(baseDate, rangeStart, rangeEnd, frequencyType, frequencyValue);
        }).toList();
      }
      
      // Apply priority and status filters if set
      if (_selectedPriority != null) {
        _filteredTasks = _filteredTasks.where((task) => task.priority == _selectedPriority).toList();
      }
      if (_selectedStatus != null) {
        _filteredTasks = _filteredTasks.where((task) => task.status == _selectedStatus).toList();
      }
    });
  }

  bool _isTaskDueOnDate(DateTime dueDate, DateTime selectedDate, String frequencyType, int? frequencyValue) {
    if (frequencyValue == null) return false;
    
    // Normalize dates to compare only dates (ignore time)
    final normalizedDue = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final normalizedSelected = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    
    switch (frequencyType) {
      case 'daily':
        // Every N days - selected date must be on or after the base date
        if (normalizedSelected.isBefore(normalizedDue)) return false;
        final daysDiff = normalizedSelected.difference(normalizedDue).inDays;
        return daysDiff % frequencyValue == 0;
      
      case 'weekly':
        // frequency_value represents day of week: 0=Sunday, 1=Monday, 2=Tuesday, etc.
        // Check if selected date's weekday matches the frequency_value
        // DateTime.weekday: 1=Monday, 2=Tuesday, ..., 7=Sunday
        // We need to convert: frequency_value 0=Sunday, 1=Monday, 2=Tuesday, etc.
        // So: frequency_value 0 -> weekday 7, frequency_value 1 -> weekday 1, etc.
        // For weekly, we don't need to check if selected date is before due date
        // because we're just checking if the weekday matches
        final selectedWeekday = normalizedSelected.weekday;
        final targetWeekday = frequencyValue == 0 ? 7 : frequencyValue;
        return selectedWeekday == targetWeekday;
      
      case 'monthly':
        // frequency_value represents day of month (e.g., 1 = every 1st of the month)
        // Check if selected date's day matches the frequency_value
        // For monthly tasks, we don't check if selected date is before due date
        // because we want to show the task on the specified day of every month
        return normalizedSelected.day == frequencyValue;
      
      default:
        // For other types, check if dates match exactly
        if (normalizedSelected.isBefore(normalizedDue)) return false;
        return normalizedSelected.isAtSameMomentAs(normalizedDue);
    }
  }

  Set<DateTime> _getDatesWithTasks() {
    final dates = <DateTime>{};
    
    for (var task in _allRecurringTasks) {
      final frequencyType = task.frequencyType;
      final frequencyValue = task.frequencyValue;

      if (frequencyValue == null) continue;
      if (frequencyType == 'none' || frequencyType.isEmpty) continue;
      
      DateTime? baseDate;
      if (task.dueDate != null) {
        baseDate = _safeParseDate(task.dueDate);
      } else if (frequencyType == 'monthly' ||
          frequencyType == 'daily' ||
          frequencyType == 'weekly') {
        final c = task.createdAt;
        baseDate = DateTime(c.year, c.month, c.day);
      } else {
        continue;
      }
      if (baseDate == null) continue;
      
      final dueDate = baseDate;
      
      // Generate dates for the next 3 months
      final now = DateTime.now();
      final startDate = now.subtract(Duration(days: 30)); // Also show past month
      final endDate = now.add(Duration(days: 90));
      
      switch (frequencyType) {
        case 'daily':
          // Every N days
          DateTime currentDate = dueDate;
          while (currentDate.isBefore(endDate) || currentDate.isAtSameMomentAs(endDate)) {
            if (currentDate.isAfter(startDate.subtract(Duration(days: 1))) || 
                currentDate.isAtSameMomentAs(startDate)) {
              dates.add(DateTime(currentDate.year, currentDate.month, currentDate.day));
            }
            currentDate = currentDate.add(Duration(days: frequencyValue));
          }
          break;
          
        case 'weekly':
          // frequency_value represents day of week: 0=Sunday, 1=Monday, 2=Tuesday, etc.
          // Convert to DateTime.weekday format: 0=Sunday -> 7, 1=Monday -> 1, etc.
          final targetWeekday = frequencyValue == 0 ? 7 : frequencyValue;
          
          // Start from startDate and find all matching weekdays until endDate
          DateTime currentDate = startDate;
          
          // Find the first occurrence of the target weekday
          // Formula: (targetWeekday - currentDate.weekday + 7) % 7
          // This handles all cases: same day (0), future day in same week, or next week
          int daysUntilTarget = (targetWeekday - currentDate.weekday + 7) % 7;
          currentDate = currentDate.add(Duration(days: daysUntilTarget));
          
          // Add all occurrences of this weekday within the date range
          while (currentDate.isBefore(endDate) || currentDate.isAtSameMomentAs(endDate)) {
            dates.add(DateTime(currentDate.year, currentDate.month, currentDate.day));
            currentDate = currentDate.add(Duration(days: 7)); // Move to next week
          }
          break;
          
        case 'monthly':
          // frequency_value represents day of month (e.g., 7 = every 7th of the month)
          DateTime currentDate = startDate;
          // Start from the first day of the startDate's month
          currentDate = DateTime(currentDate.year, currentDate.month, 1);
          
          while (currentDate.isBefore(endDate) || currentDate.isAtSameMomentAs(endDate)) {
            // Get the target day of month, but handle months with fewer days
            int targetDay = frequencyValue;
            int daysInMonth = DateTime(currentDate.year, currentDate.month + 1, 0).day;
            if (targetDay > daysInMonth) {
              targetDay = daysInMonth; // Use last day of month if target day doesn't exist
            }
            
            DateTime taskDate = DateTime(currentDate.year, currentDate.month, targetDay);
            
            if (taskDate.isAfter(startDate.subtract(Duration(days: 1))) && 
                (taskDate.isBefore(endDate) || taskDate.isAtSameMomentAs(endDate))) {
              dates.add(DateTime(taskDate.year, taskDate.month, taskDate.day));
            }
            
            // Move to next month
            currentDate = DateTime(currentDate.year, currentDate.month + 1, 1);
          }
          break;
          
        default:
          // For non-recurring or unknown types, just add the due date if it's in range
          if (dueDate.isAfter(startDate.subtract(Duration(days: 1))) && 
              (dueDate.isBefore(endDate) || dueDate.isAtSameMomentAs(endDate))) {
            dates.add(DateTime(dueDate.year, dueDate.month, dueDate.day));
          }
          break;
      }
    }
    
    return dates;
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white, size: 22),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Color(0xFFEF476F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 6,
      ),
    );
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Давтамжит Даалгавар',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: Colors.grey[800],
            ),
          ),
          if (_userName != null)
            Text(
              'Сайн байна уу, $_userName!',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w500,
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
        ],
      ),
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      actions: [
        if (_rangeStartDate != null)
          IconButton(
            icon: Icon(Icons.event_busy, color: Colors.grey[700], size: 24),
            onPressed: () => _filterTasksByRange(startDate: null, endDate: null),
            tooltip: 'Огны шүүлт цэвэрлэх',
          ),
        IconButton(
          icon: Icon(Icons.filter_list, color: Colors.grey[700], size: 24),
          onPressed: _showFilterDialog,
          tooltip: 'Шүүлт',
        ),
      ],
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Шүүлт',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[800],
                      ),
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Эрэмбийн зэрэг:',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _buildFilterChip('high', 'Өндөр', _selectedPriority == 'high', (selected) {
                          setDialogState(() {
                            _selectedPriority = selected ? 'high' : null;
                          });
                        }),
                        _buildFilterChip('normal', 'Хэвийн', _selectedPriority == 'normal', (selected) {
                          setDialogState(() {
                            _selectedPriority = selected ? 'normal' : null;
                          });
                        }),
                        _buildFilterChip('low', 'Бага', _selectedPriority == 'low', (selected) {
                          setDialogState(() {
                            _selectedPriority = selected ? 'low' : null;
                          });
                        }),
                      ],
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Төлөв:',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _buildFilterChip('pending', 'Хүлээгдэж байна', _selectedStatus == 'pending', (selected) {
                          setDialogState(() {
                            _selectedStatus = selected ? 'pending' : null;
                          });
                        }),
                        _buildFilterChip('in_progress', 'Хийгдэж байна', _selectedStatus == 'in_progress', (selected) {
                          setDialogState(() {
                            _selectedStatus = selected ? 'in_progress' : null;
                          });
                        }),
                        _buildFilterChip('done', 'Дууссан', _selectedStatus == 'done', (selected) {
                          setDialogState(() {
                            _selectedStatus = selected ? 'done' : null;
                          });
                        }),
                        _buildFilterChip('verified', 'Баталгаажсан', _selectedStatus == 'verified', (selected) {
                          setDialogState(() {
                            _selectedStatus = selected ? 'verified' : null;
                          });
                        }),
                      ],
                    ),
                    SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setDialogState(() {
                                _selectedPriority = null;
                                _selectedStatus = null;
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey[600],
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text('Цэвэрлэх', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _filterTasksByRange(startDate: _rangeStartDate, endDate: _rangeEndDate);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF4ECDC4),
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text('Хэрэглэх', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterChip(String value, String label, bool selected, Function(bool) onChanged) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onChanged,
      selectedColor: Color(0xFF4ECDC4).withOpacity(0.2),
      checkmarkColor: Color(0xFF4ECDC4),
    );
  }

  Widget _buildTaskCard(Task task) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _showTaskDetailModal(task);
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            style: GoogleFonts.inter(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[800],
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (task.description != null && task.description!.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(
                                task.description!,
                                style: GoogleFonts.inter(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(width: 12),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _statusColors[task.status]!.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _statusColors[task.status]!.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        task.formattedStatus,
                        style: GoogleFonts.inter(
                          color: _statusColors[task.status],
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _priorityColors[task.priority]!.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.flag,
                            size: 14,
                            color: _priorityColors[task.priority],
                          ),
                          SizedBox(width: 6),
                          Text(
                            task.formattedPriority,
                            style: GoogleFonts.inter(
                              color: _priorityColors[task.priority],
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (task.dueDate != null)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: task.isOverdue
                              ? Color(0xFFE53935).withOpacity(0.08)
                              : Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: task.isOverdue
                                ? Color(0xFFE53935).withOpacity(0.35)
                                : Colors.grey[200]!,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: task.isOverdue
                                  ? Color(0xFFE53935)
                                  : Colors.grey[600],
                            ),
                            SizedBox(width: 6),
                            Text(
                              _formatDate(DateTime.parse(task.dueDate!)),
                              style: GoogleFonts.inter(
                                color: task.isOverdue
                                    ? Color(0xFFE53935)
                                    : Colors.grey[600],
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (task.timelinessLabel != null)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: (task.isOverdue || task.wasCompletedLate
                                  ? Color(0xFFE53935)
                                  : Color(0xFF43A047))
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: (task.isOverdue || task.wasCompletedLate
                                    ? Color(0xFFE53935)
                                    : Color(0xFF43A047))
                                .withOpacity(0.35),
                          ),
                        ),
                        child: Text(
                          task.timelinessLabel!,
                          style: GoogleFonts.inter(
                            color: task.isOverdue || task.wasCompletedLate
                                ? Color(0xFFE53935)
                                : Color(0xFF43A047),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Color(0xFF4ECDC4).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.repeat, size: 14, color: Color(0xFF4ECDC4)),
                          SizedBox(width: 6),
                          Text(
                            task.formattedFrequency,
                            style: GoogleFonts.inter(
                              color: Color(0xFF4ECDC4),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTaskDetailModal(Task task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Даалгаврын дэлгэрэнгүй',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[800],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 24),
                      color: Colors.grey[600],
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey[200]),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[900],
                        ),
                      ),
                      SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: _statusColors[task.status]!.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _statusColors[task.status]!.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: _statusColors[task.status],
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  task.formattedStatus,
                                  style: GoogleFonts.inter(
                                    color: _statusColors[task.status],
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: _priorityColors[task.priority]!.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.flag,
                                  size: 16,
                                  color: _priorityColors[task.priority],
                                ),
                                SizedBox(width: 6),
                                Text(
                                  task.formattedPriority,
                                  style: GoogleFonts.inter(
                                    color: _priorityColors[task.priority],
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 24),
                      if (task.description != null && task.description!.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Тайлбар:',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                            SizedBox(height: 8),
                            Container(
                              padding: EdgeInsets.all(16),
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                task.description!,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  color: Colors.grey[600],
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      SizedBox(height: 24),
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Мэдээлэл:',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                            SizedBox(height: 12),
                            if (task.dueDate != null)
                              _buildDetailRow(
                                icon: Icons.calendar_today,
                                title: 'Дуусах хугацаа:',
                                value: _formatDate(DateTime.parse(task.dueDate!)),
                                color: task.isOverdue
                                    ? Color(0xFFE53935)
                                    : Colors.grey,
                              ),
                            if (task.timelinessLabel != null) ...[
                              SizedBox(height: 10),
                              _buildDetailRow(
                                icon: task.isOverdue || task.wasCompletedLate
                                    ? Icons.warning_amber_rounded
                                    : Icons.check_circle_outline,
                                title: 'Хугацааны төлөв:',
                                value: task.timelinessLabel!,
                                color: task.isOverdue || task.wasCompletedLate
                                    ? Color(0xFFE53935)
                                    : Color(0xFF43A047),
                              ),
                            ],
                            if (task.dueDate != null) SizedBox(height: 10),
                            _buildDetailRow(
                              icon: Icons.repeat,
                              title: 'Давтамж:',
                              value: task.frequencyValue != null 
                                  ? '${task.formattedFrequency} (${task.frequencyValue})'
                                  : task.formattedFrequency,
                              color: Colors.grey,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 24),
                      // Status update buttons for workers
                      if (_userRole != null && (_userRole == 'worker' || _userRole == 'supervisor' || _userRole == 'manager' || _userRole == 'director' || _userRole == 'general_manager' || _userRole == 'admin'))
                        Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Төлөв өөрчлөх:',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[700],
                                ),
                              ),
                              SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (task.status != 'pending')
                                    _buildStatusButton(
                                      task: task,
                                      status: 'pending',
                                      label: 'Хүлээгдэж байна',
                                      color: _statusColors['pending']!,
                                    ),
                                  if (task.status != 'in_progress')
                                    _buildStatusButton(
                                      task: task,
                                      status: 'in_progress',
                                      label: 'Хийгдэж байна',
                                      color: _statusColors['in_progress']!,
                                    ),
                                  if (task.status != 'done')
                                    _buildStatusButton(
                                      task: task,
                                      status: 'done',
                                      label: 'Дууссан',
                                      color: _statusColors['done']!,
                                    ),
                                  if (task.status == 'done' &&
                                      (_userRole ?? '').toLowerCase() == 'supervisor')
                                    _buildStatusButton(
                                      task: task,
                                      status: 'verified',
                                      label: 'Баталгаажсан',
                                      color: _statusColors['verified']!,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusButton({
    required Task task,
    required String status,
    required String label,
    required Color color,
  }) {
    return ElevatedButton(
      onPressed: () {
        Navigator.of(context).pop(); // Close detail modal first
        _changeTaskStatus(task, status);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.1),
        foregroundColor: color,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withOpacity(0.3)),
        ),
        elevation: 0,
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }

  Future<void> _changeTaskStatus(Task task, String newStatus) async {
    if (newStatus == 'cancelled' &&
        (_userRole ?? '').toLowerCase() == 'worker') {
      _showErrorSnackBar('Таны эрх хүрэхгүй байна');
      return;
    }

    // Only supervisors can verify completed tasks.
    if (newStatus == 'verified') {
      final role = (_userRole ?? '').toLowerCase();
      if (role != 'supervisor') {
        _showErrorSnackBar('"Баталгаажсан" төлөвийг зөвхөн supervisor өөрчилнө');
        return;
      }
      if (task.status != 'done') {
        _showErrorSnackBar('"Баталгаажсан" болгохын өмнө даалгавар "Дууссан" байх шаардлагатай');
        return;
      }
    }

    // Check if status is "done" - require image
    if (newStatus == 'done') {
      final XFile? image = await _showCameraDialog();

      if (image == null) {
        _showErrorSnackBar('"Дууссан" төлөв рүү шилжихэд зураг шаардлагатай');
        return;
      }

      await _updateTaskStatusWithImage(task.id, newStatus, image);
    } else {
      // For other statuses, just update without image
      await _updateTaskStatusWithoutImage(task.id, newStatus);
    }
  }

  Future<XFile?> _showCameraDialog() async {
    return showDialog<XFile>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 8,
          child: Container(
            padding: EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Color(0xFF4ECDC4).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.photo_camera,
                    size: 32,
                    color: Color(0xFF4ECDC4),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'Статус өөрчлөх',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[800],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Статус өөрчлөхөд зураг авах шаардлагатай',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: Colors.grey[600],
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.grey[300]!),
                        ),
                        child: Text(
                          'Цуцлах',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          try {
                            final cameraStatus = await Permission.camera.request();
                            if (!cameraStatus.isGranted) {
                              if (cameraStatus.isPermanentlyDenied ||
                                  cameraStatus.isRestricted) {
                                final openSettings = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text('Камерын зөвшөөрөл хаалттай',
                                        style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                                    content: Text(
                                      'Камер ашиглахын тулд Settings дотроос зөвшөөрөл нээнэ үү.\n\n'
                                      'Хэрэв iOS Simulator дээр taskmanager апп харагдахгүй бол "Runner" нэрээр байж болно. '
                                      'Мөн аппыг устгаад дахин суулгах эсвэл Simulator privacy reset хийж үзнэ үү.',
                                      style: GoogleFonts.inter(),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(ctx).pop(false),
                                        child: Text('Буцах', style: GoogleFonts.inter()),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.of(ctx).pop(true),
                                        child: Text('Settings нээх', style: GoogleFonts.inter()),
                                      ),
                                    ],
                                  ),
                                );
                                if (openSettings == true) {
                                  await openAppSettings();
                                }
                              }
                              return;
                            }

                            final XFile? image = await _picker.pickImage(
                              source: ImageSource.camera,
                              preferredCameraDevice: CameraDevice.rear,
                              maxWidth: 800,
                              imageQuality: 85,
                            );
                            Navigator.of(context).pop(image);
                          } catch (e) {
                            Navigator.of(context).pop();
                            _showErrorSnackBar('Зураг авахад алдаа гарлаа: $e');
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF4ECDC4),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.camera_alt, size: 20),
                            SizedBox(width: 6),
                            Text(
                              'Зураг авах',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _updateTaskStatusWithoutImage(int taskId, String newStatus) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: EdgeInsets.all(24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4ECDC4)),
                ),
                SizedBox(width: 20),
                Expanded(
                  child: Text(
                    "Төлөв шинэчлэгдэж байна...",
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        Navigator.of(context).pop();
        _showErrorSnackBar('Нэвтрэх эрх шаардлагатай');
        return;
      }

      print('🔄 Updating task status without image...');
      print('🎯 Task ID: $taskId, Status: $newStatus');

      final url = Uri.parse('${Url.url}/api/task/$taskId/status?status=$newStatus');
      print('🔗 URL: $url');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json'
        },
        body: json.encode({}),
      );

      Navigator.of(context).pop();

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        if (jsonResponse['success'] == true) {
          _showSuccessSnackBar('Төлөв амжилттай шинэчлэгдлээ 🎉');
          await _fetchTasks();
        } else {
          throw Exception(jsonResponse['message'] ?? 'Алдаа гарлаа');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to update status: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error updating status without image: $e');
      Navigator.of(context).pop();
      _showErrorSnackBar('Төлөв шинэчлэхэд алдаа гарлаа: $e');
    }
  }

  Future<void> _updateTaskStatusWithImage(int taskId, String newStatus, XFile image) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        child: Container(
          padding: EdgeInsets.all(24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("Ачааллаж байна..."),
            ],
          ),
        ),
      ),
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        Navigator.of(context).pop();
        _showErrorSnackBar('Нэвтрэх эрх шаардлагатай');
        return;
      }

      print('🔄 Updating task status...');

      final url = Uri.parse('${Url.url}/api/task/$taskId/status?status=$newStatus');
      var request = http.MultipartRequest('POST', url);

      request.headers['Authorization'] = 'Bearer $token';

      var imageBytes = await image.readAsBytes();
      var multipartFile = http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: 'task_image_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      request.files.add(multipartFile);

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      Navigator.of(context).pop();

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        if (jsonResponse['success'] == true) {
          _showSuccessSnackBar('Төлөв амжилттай шинэчлэгдлээ 🎉');
          await _fetchTasks();
        } else {
          throw Exception(jsonResponse['message'] ?? 'Алдаа гарлаа');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to update status: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error updating status with image: $e');
      Navigator.of(context).pop();
      _showErrorSnackBar('Төлөв шинэчлэхэд алдаа гарлаа: $e');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white, size: 22),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Color(0xFF06D6A0),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 6,
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color.withOpacity(0.7)),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: color.withOpacity(0.9),
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 4),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: Colors.grey[800],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4ECDC4)),
                    strokeWidth: 3,
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Даалгаврууд ачааллаж байна...',
                    style: GoogleFonts.inter(
                      color: Colors.grey[600],
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchTasks,
              color: Color(0xFF4ECDC4),
              backgroundColor: Colors.white,
              displacement: 40,
              child: Column(
                children: [
                  // Calendar View
                  Container(
                    margin: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 20,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: SfDateRangePicker(
                      view: DateRangePickerView.month,
                      selectionMode: DateRangePickerSelectionMode.range,
                      initialSelectedRange: _rangeStartDate == null
                          ? null
                          : PickerDateRange(_rangeStartDate, _rangeEndDate ?? _rangeStartDate),
                      onSelectionChanged: (DateRangePickerSelectionChangedArgs args) {
                        if (args.value is PickerDateRange) {
                          final selected = args.value as PickerDateRange;
                          final start = selected.startDate;
                          final end = selected.endDate ?? selected.startDate;
                          print('📅 Calendar range selected: $start -> $end');
                          _filterTasksByRange(startDate: start, endDate: end);
                        }
                      },
                      monthViewSettings: DateRangePickerMonthViewSettings(
                        showTrailingAndLeadingDates: true,
                        // Highlight dates with tasks - specialDates will mark dates with a different style
                        specialDates: _getDatesWithTasks().toList(),
                      ),
                      headerStyle: DateRangePickerHeaderStyle(
                        textStyle: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      selectionTextStyle: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                      ),
                      todayHighlightColor: Color(0xFF4ECDC4),
                      selectionColor: Color(0xFF4ECDC4),
                      rangeSelectionColor: Color(0xFF4ECDC4).withOpacity(0.3),
                    ),
                  ),

                  SizedBox(height: 16),
                  
                  // Tasks list
                  Expanded(
                    child: _filteredTasks.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.assignment_outlined,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                SizedBox(height: 16),
                                Text(
                                  _rangeStartDate == null
                                      ? 'Даалгавар олдсонгүй'
                                      : 'Даалгавар байхгүй',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  _rangeStartDate == null
                                      ? 'Давтамжит даалгавар байхгүй байна'
                                      : 'Календарын сонголтод тохирох даалгавар алга',
                                  style: GoogleFonts.inter(
                                    color: Colors.grey[500],
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.all(16),
                            itemCount: _filteredTasks.length,
                            separatorBuilder: (context, index) => SizedBox(height: 16),
                            itemBuilder: (context, index) {
                              return _buildTaskCard(_filteredTasks[index]);
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

