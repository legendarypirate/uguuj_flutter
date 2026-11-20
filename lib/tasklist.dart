// tasklist.dart
import 'dart:async';
import 'dart:math' as Math;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:taskmanager/push_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart'; // Add this import
import 'package:intl/intl.dart'; // Add this for date formatting
import 'color/color.dart';
import 'models/task.dart';
import 'notification.dart' as notification_screen;
import 'login.dart' as auth; // Use an alias to avoid conflicts
import 'package:http_parser/http_parser.dart'; // Add this import for MediaType

class TaskListScreen extends StatefulWidget {
  @override
  _TaskListScreenState createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Task> _tasks = [];
  List<Task> _filteredTasks = [];
  bool _isLoading = true;
  int? _currentUserId;
  String? _userName;
  String? _userRole; // Add user role variable
  final List<String> _statusTabs = ['pending', 'in_progress', 'done', 'verified', 'cancelled'];
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

  // Add user list variable
  List<auth.User> _workers = []; // Use auth.User for clarity
  bool _isLoadingWorkers = false;

  /// Resolved users by id (loaded for director / GM / supervisor / manager / admin).
  Map<int, auth.User> _userById = {};

  // Modern color palette
  final Map<String, Color> _statusColors = {
    'pending': Color(0xFFFF6B35), // Vibrant Orange
    'in_progress': Color(0xFF4ECDC4), // Teal
    'done': Color(0xFF06D6A0), // Emerald
    'verified': Color(0xFF9D4EDD), // Purple
    'cancelled': Color(0xFFEF476F), // Pink Red
  };

  final Map<String, Color> _priorityColors = {
    'high': Color(0xFFEF476F), // Red
    'normal': Color(0xFFFFD166), // Yellow
    'low': Color(0xFF06D6A0), // Green
  };

  // Add variable to store task image URLs
  Map<int, String?> _taskImageUrls = {};
  int _unreadNotificationCount = 0;
  StreamSubscription<RemoteMessage>? _foregroundPushSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statusTabs.length, vsync: this);
    _tabController.addListener(_handleTabSelection);
    _foregroundPushSub = PushService.foregroundMessages.listen((_) {
      _refreshUnreadNotificationCount();
    });
    _loadUserAndTasks();
  }

  Future<void> _loadUserAndTasks() async {
    try {
      // Get user ID from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('userId');
      final userName = prefs.getString('userName');
      final userRole = prefs.getString('role'); // Get user role

      if (userId == null) {
        print('❌ User ID not found in SharedPreferences');
        // Handle case where user is not logged in
        _showErrorSnackBar('Хэрэглэгч нэвтрээгүй байна');
        return;
      }

      setState(() {
        _currentUserId = userId;
        _userName = userName;
        _userRole = userRole; // Store user role
      });

      print('👤 Loaded user from SharedPreferences: ID=$userId, Name=$userName, Role=$userRole');

      // Now fetch tasks
      await _fetchTasks();
      await _refreshUnreadNotificationCount();
    } catch (e) {
      print('❌ Error loading user data: $e');
      _showErrorSnackBar('Хэрэглэгчийн мэдээлэл ачааллахад алдаа гарлаа');
    }
  }

  Future<void> _refreshUnreadNotificationCount() async {
    final count = await notification_screen.fetchUnreadNotificationCount();
    if (!mounted) return;
    setState(() {
      _unreadNotificationCount = count;
    });
  }

  Future<void> _openNotificationScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => notification_screen.NotificationScreen(),
      ),
    );
    await _refreshUnreadNotificationCount();
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) {
      _filterTasksByStatus(_statusTabs[_tabController.index]);
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

      print('🔄 Fetching tasks for user ID: $_currentUserId, Role: $_userRole');
      final response = await http.get(Uri.parse(Url.url+'/api/task'));

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        final List<dynamic> tasksJson = jsonData['data'] ?? [];

        List<dynamic> userTasks = [];

        // Check if user is director or general_manager
        if (_userRole == 'director' || _userRole == 'general_manager') {
          // For director and general_manager, show ALL tasks
          print('👑 Director/General Manager detected - showing ALL tasks');
          userTasks = tasksJson;
        } else if (_userRole == 'supervisor') {
          // Tasks visible to supervisor:
          // 1) directly assigned to supervisor (assigned_to = supervisor id)
          // 2) legacy supervisor link (supervisor_id = supervisor id)
          // 3) assigned to subordinate workers of this supervisor
          Set<int> subordinateIds = {};
          try {
            final allWorkers = await auth.AuthService.getWorkers();
            subordinateIds = allWorkers
                .where((w) =>
                    w.role.toLowerCase() == 'worker' &&
                    w.supervisor_id.contains(_currentUserId))
                .map((w) => w.id)
                .toSet();
            print('👥 Supervisor subordinate worker IDs: $subordinateIds');
          } catch (e) {
            print('⚠️ Could not load subordinate workers for visibility: $e');
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
          // For workers and other roles, show tasks where assigned_to contains current user's ID
          userTasks = tasksJson.where((taskJson) {
            final assignedToList = _toIntList(taskJson['assigned_to']);
            return assignedToList.contains(_currentUserId);
          }).toList();
        }

        // Давтамжит загвар биш бүх ажил (нэг удаа, due_date-тай гэх мэт) — давтамжит дэлгэцээс тусад нь.
        bool isRecurringTemplate(dynamic taskJson) {
          final ft = taskJson['frequency_type']?.toString() ?? '';
          final fv = taskJson['frequency_value'];
          return ft.isNotEmpty &&
              ft != 'none' &&
              fv != null;
        }

        final nonRecurringTasks =
            userTasks.where((taskJson) => !isRecurringTemplate(taskJson)).toList();

        print('✅ Loaded ${nonRecurringTasks.length} non-recurring tasks for user ID: $_currentUserId, Role: $_userRole');
        print('📊 Total tasks in API: ${tasksJson.length}');

        Map<int, auth.User> userById = {};
        try {
          final all = await auth.AuthService.fetchAllUsers();
          userById = {for (final u in all) u.id: u};
        } catch (e) {
          print('⚠️ Could not load users for task labels: $e');
        }

        // Clear existing task images
        _taskImageUrls.clear();

        setState(() {
          _userById = userById;
          _tasks = nonRecurringTasks.map((taskJson) => Task.fromJson(taskJson)).toList();
          _filterTasksByStatus(_statusTabs[_tabController.index]);
          _isLoading = false;
        });

        // Load task images for tasks with "done" status
        await _loadTaskImages();
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

  // Method to load task images for "done" tasks
  Future<void> _loadTaskImages() async {
    try {
      for (var task in _tasks) {
        if (task.status == 'done' || task.status == 'verified') {
          final imageUrl = await _fetchTaskImage(task.id);
          if (imageUrl != null) {
            _taskImageUrls[task.id] = imageUrl;
          }
        }
      }
      setState(() {});
    } catch (e) {
      print('❌ Error loading task images: $e');
    }
  }

  // Method to fetch task image URL
  Future<String?> _fetchTaskImage(int taskId) async {
    try {
      final response = await http.get(
        Uri.parse('${Url.url}/api/task/$taskId/image'),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        if (jsonData['success'] == true && jsonData['data'] != null) {
          return jsonData['data']['url'];
        }
      }
      return null;
    } catch (e) {
      print('❌ Error fetching task image: $e');
      return null;
    }
  }

  // Add method to fetch workers - only show subordinates of current supervisor
  Future<void> _fetchWorkers() async {
    try {
      setState(() {
        _isLoadingWorkers = true;
      });

      print('🔄 Fetching workers list for supervisor ID: $_currentUserId');

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        _showErrorSnackBar('Нэвтрэх эрх шаардлагатай');
        setState(() {
          _isLoadingWorkers = false;
        });
        return;
      }

      // Fetch ALL workers first
      final allWorkers = await auth.AuthService.getWorkers();

      print('📊 Total workers from API: ${allWorkers.length}');

      // Filter workers to show only subordinates of current supervisor
      final subordinates = allWorkers.where((worker) {
        // Only show workers (role = "worker")
        final isWorker = worker.role.toLowerCase() == 'worker';

        // Check if this worker's supervisor_id matches current user's ID
        final isSubordinate = worker.supervisor_id.contains(_currentUserId);

        if (isWorker && isSubordinate) {
          print('   ✅ Found subordinate: ${worker.full_name} (Supervisor ID: ${worker.supervisor_id})');
        }

        return isWorker && isSubordinate;
      }).toList();

      print('✅ Found ${subordinates.length} subordinates for supervisor ID: $_currentUserId');

      setState(() {
        _workers = subordinates;
        _isLoadingWorkers = false;
      });

    } catch (e) {
      print('❌ Error fetching workers: $e');
      print('❌ Error type: ${e.runtimeType}');
      print('❌ Stack trace: ${StackTrace.current}');

      setState(() {
        _isLoadingWorkers = false;
      });
      _showErrorSnackBar('Ажилчдын мэдээлэл ачааллахад алдаа гарлаа: ${e.toString()}');
    }
  }

  // Add method to assign task to worker
  Future<void> _assignTaskToWorker(int taskId, int workerId) async {
    try {
      // Get token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        _showErrorSnackBar('Нэвтрэх эрх шаардлагатай');
        return;
      }

      final response = await http.patch(
        Uri.parse(Url.url+'/api/task/$taskId/assign'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'assigned_to': workerId,
        }),
      );

      if (response.statusCode == 200) {
        _showSuccessSnackBar('Даалгавар амжилттай хуваарилагдлаа 🎉');
        // Refresh the task list
        await _fetchTasks();
      } else {
        throw Exception('Failed to assign task: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error assigning task: $e');
      _showErrorSnackBar('Даалгавар хуваарилахад алдаа гарлаа: $e');
    }
  }

  // Add method to check if user can assign tasks
  bool _canCancelTasks() {
    final role = (_userRole ?? '').toLowerCase();
    return role != 'worker';
  }

  bool _canAssignTasks() {
    if (_userRole == null) return false;

    // Define which roles can assign tasks (managers, supervisors, directors, etc.)
    final assignerRoles = [
      'general_manager',
      'director',
      'supervisor',
      'manager',
      'admin'
    ];

    // Convert role to lowercase for case-insensitive comparison
    final userRoleLower = _userRole!.toLowerCase();

    // Check if user role is in assigner roles
    final canAssign = assignerRoles.contains(userRoleLower);

    print('👑 User role check: $_userRole -> canAssign: $canAssign');
    return canAssign;
  }

  /// Director, GM, supervisor (and other assigners) see which **workers** are assigned.
  bool _shouldShowWorkerAssigneesOnCards() {
    const allowed = {
      'general_manager',
      'director',
      'supervisor',
      'manager',
      'admin',
    };
    final r = _userRole?.toLowerCase();
    return r != null && allowed.contains(r);
  }

  String _roleLabelMn(String role) {
    switch (role.toLowerCase()) {
      case 'worker':
        return 'Ажилтан';
      case 'supervisor':
        return 'Ахлах';
      case 'general_manager':
        return 'Ерөнхий менежер';
      case 'director':
        return 'Захирал';
      default:
        return role;
    }
  }

  /// Names of assignees whose role is **worker** only; null if none.
  String? _workerAssigneesLabel(Task task) {
    if (!_shouldShowWorkerAssigneesOnCards()) return null;
    if (task.assignedTo.isEmpty) return null;
    final parts = <String>[];
    for (final id in task.assignedTo.toSet()) {
      if (id == 0) continue;
      final u = _userById[id];
      if (u != null && u.role.toLowerCase() == 'worker') {
        final name = u.full_name.trim().isEmpty ? 'ID $id' : u.full_name.trim();
        parts.add('$name · ${_roleLabelMn(u.role)}');
      }
    }
    if (parts.isEmpty) return null;
    return parts.join('\n');
  }

  static const _assignerRoles = {
    'supervisor',
    'general_manager',
    'director',
    'manager',
    'admin',
  };

  /// `created_by` — даалгавар олгосон удирдлага (ахлах/захирал г.м). Зөвхөн эдгээр эрхтэй хэрэглэгч харагдана.
  String? _taskCreatorSupervisorLabel(Task task) {
    if (task.createdBy == 0) return null;
    final u = _userById[task.createdBy];
    if (u == null) return null;
    if (!_assignerRoles.contains(u.role.toLowerCase())) return null;
    final name = u.full_name.trim().isEmpty ? 'ID ${task.createdBy}' : u.full_name.trim();
    return '$name · ${_roleLabelMn(u.role)}';
  }

  // Add method to show assign worker dialog
  void _showAssignWorkerDialog(Task task) {
    // First fetch workers, then show dialog
    _fetchWorkers().then((_) {
      if (_workers.isEmpty) {
        _showNoSubordinatesDialog();
        return;
      }

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return Dialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 8,
                child: Container(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with supervisor info
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Хуваарилах',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey[800],
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '"${task.title}" даалгаврыг өөрийн удирдлагад ажилчид руу',
                            style: GoogleFonts.inter(
                              color: Colors.grey[600],
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          SizedBox(height: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Color(0xFF4ECDC4).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.people, size: 16, color: Color(0xFF4ECDC4)),
                                SizedBox(width: 6),
                                Text(
                                  '${_workers.length} ажилтан байна',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: Color(0xFF4ECDC4),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 20),

                      // Workers list section
                      Expanded(
                        child: _isLoadingWorkers
                            ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4ECDC4)),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Өөрийн ажилчдын мэдээлэл ачаалж байна...',
                                  style: GoogleFonts.inter(
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                            : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _workers.length,
                          itemBuilder: (context, index) {
                            final worker = _workers[index];
                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Color(0xFF4ECDC4).withOpacity(0.1),
                                  child: Text(
                                    worker.full_name.isNotEmpty
                                        ? worker.full_name[0].toUpperCase()
                                        : '?',
                                    style: GoogleFonts.inter(
                                      color: Color(0xFF4ECDC4),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  worker.full_name,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Утас: ${worker.phone}',
                                      style: GoogleFonts.inter(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Ажилтан',
                                        style: GoogleFonts.inter(
                                          color: Colors.grey[700],
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: task.assignedTo.contains(worker.id)
                                    ? Icon(Icons.check_circle, color: Color(0xFF06D6A0))
                                    : null,
                                tileColor: Colors.grey[50],
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  _showConfirmAssignDialog(task, worker);
                                },
                              ),
                            );
                          },
                        ),
                      ),

                      SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey[600],
                                padding: EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(color: Colors.grey[300]!),
                              ),
                              child: Text(
                                'Цуцлах',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                // Use setState from StatefulBuilder to update the dialog
                                setState(() {
                                  _isLoadingWorkers = true;
                                });
                                await _fetchWorkers();
                                setState(() {
                                  _isLoadingWorkers = false;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(0xFF4ECDC4),
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.refresh, size: 18),
                                  SizedBox(width: 6),
                                  Text(
                                    'Шинэчлэх',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
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
        },
      );
    }).catchError((e) {
      print('❌ Error showing assign dialog: $e');
      _showErrorSnackBar('Хуваарилах цонхыг нээхэд алдаа гарлаа');
    });
  }

  // Add method to show when supervisor has no subordinates
  void _showNoSubordinatesDialog() {
    showDialog(
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
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Color(0xFFFFD166).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.people_outline,
                    size: 40,
                    color: Color(0xFFFFD166),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'Удирдлагад ажилтан байхгүй',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[800],
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Таны удирдлагад ажилтан бүртгэгдээгүй байна. Даалгавар хуваарилахын тулд эхлээд ажилтан нэмнэ үү.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: Colors.grey[600],
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey[600],
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.grey[300]!),
                        ),
                        child: Text(
                          'Хаах',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                          ),
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

  // Add method to show confirmation dialog
  void _showConfirmAssignDialog(Task task, auth.User worker) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 8,
          child: Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Color(0xFF4ECDC4).withOpacity(0.1),
                  child: Icon(
                    Icons.person_add_alt_1,
                    size: 36,
                    color: Color(0xFF4ECDC4),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'Хуваарилах',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[800],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '"${task.title}" даалгаврыг',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: Colors.grey[600],
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '"${worker.full_name}" ажилчид хуваарилах уу?',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: Colors.grey[600],
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey[600],
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.grey[300]!),
                        ),
                        child: Text(
                          'Үгүй',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _assignTaskToWorker(task.id, worker.id);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF4ECDC4),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Тийм',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                          ),
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

  // Add method to show task detail modal
  void _showTaskDetailModal(Task task) {
    final assigneeDetailLine = _workerAssigneesLabel(task);
    final creatorSupervisorLine = _taskCreatorSupervisorLabel(task);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return GestureDetector(
          onTap: () {}, // Prevent dismiss on tap
          child: Container(
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
                // Drag handle
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

                // Header with close button
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

                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
                        Text(
                          task.title,
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey[900],
                          ),
                        ),

                        SizedBox(height: 16),

                        // Status and Priority Chips
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
                            if (task.timelinessLabel != null)
                              _buildTimelinessChip(task),
                          ],
                        ),
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
                                task.description ?? 'Тайлбар оруулаагүй',
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

                        // Details Grid
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

                              // Due Date
                              _buildDetailRow(
                                icon: Icons.calendar_today,
                                title: 'Дуусах хугацаа:',
                                value: task.dueDate != null
                                    ? _formatDetailedDate(task.dueDate!)
                                    : 'Тодорхойгүй',
                                color: task.isOverdue ? Color(0xFFE53935) : Colors.grey,
                              ),
                              if (task.completedAt != null) ...[
                                SizedBox(height: 10),
                                _buildDetailRow(
                                  icon: Icons.check_circle_outline,
                                  title: 'Дууссан огноо:',
                                  value: _formatDetailedDate(task.completedAt!),
                                  color: task.wasCompletedLate
                                      ? Color(0xFFFF9800)
                                      : Color(0xFF43A047),
                                ),
                              ],
                              if (task.timelinessLabel != null) ...[
                                SizedBox(height: 10),
                                _buildDetailRow(
                                  icon: task.isOverdue || task.wasCompletedLate
                                      ? Icons.warning_amber_rounded
                                      : Icons.schedule,
                                  title: 'Хугацааны төлөв:',
                                  value: task.timelinessLabel!,
                                  color: task.isOverdue || task.wasCompletedLate
                                      ? Color(0xFFE53935)
                                      : Color(0xFF43A047),
                                ),
                              ],
                              if (creatorSupervisorLine != null) ...[
                                SizedBox(height: 10),
                                _buildDetailRow(
                                  icon: Icons.assignment_ind_outlined,
                                  title: 'Даалгаварласан:',
                                  value: creatorSupervisorLine,
                                  color: Colors.grey,
                                ),
                              ],
                              if (assigneeDetailLine != null) ...[
                                SizedBox(height: 10),
                                _buildDetailRow(
                                  icon: Icons.person_outline,
                                  title: 'Гүйцэтгэгч ажилтан:',
                                  value: assigneeDetailLine.replaceAll('\n', ' · '),
                                  color: Colors.grey,
                                ),
                              ],
                              SizedBox(height: 10),

                              // Created At
                              _buildDetailRow(
                                icon: Icons.access_time,
                                title: 'Үүсгэсэн огноо:',
                                value: task.createdAt != null
                                    ? _formatDetailedDate(task.createdAt!)
                                    : 'Тодорхойгүй',
                                color: Colors.grey,
                              ),
                              SizedBox(height: 10),

                              // Updated At
                              _buildDetailRow(
                                icon: Icons.update,
                                title: 'Шинэчлэгдсэн огноо:',
                                value: task.updatedAt != null
                                    ? _formatDetailedDate(task.updatedAt!)
                                    : 'Тодорхойгүй',
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: 24),

                        // Image Section (only for done/verified tasks)
                        // In _showTaskDetailModal method, update the image section:
                        // Replace the CachedNetworkImage widget with more debugging:
                        if ((task.status == 'done' || task.status == 'verified') &&
                            task.image != null && task.image!.isNotEmpty)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Дууссан зураг:',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[700],
                                ),
                              ),
                              SizedBox(height: 12),
                              GestureDetector(
                                onTap: () {
                                  _showImageFullScreen(task.image!);
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    height: 200,
                                    width: double.infinity,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        // Try using Image.network first to see if it works
                                        Image.network(
                                          task.image!,
                                          fit: BoxFit.cover,
                                          loadingBuilder: (context, child, loadingProgress) {
                                            if (loadingProgress == null) return child;
                                            return Container(
                                              color: Colors.grey[100],
                                              child: Center(
                                                child: CircularProgressIndicator(
                                                  value: loadingProgress.expectedTotalBytes != null
                                                      ? loadingProgress.cumulativeBytesLoaded /
                                                      loadingProgress.expectedTotalBytes!
                                                      : null,
                                                  color: Color(0xFF4ECDC4),
                                                ),
                                              ),
                                            );
                                          },
                                          errorBuilder: (context, error, stackTrace) {
                                            print('❌ Image loading error: $error');
                                            return Container(
                                              color: Colors.grey[100],
                                              child: Center(
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons.image_not_supported,
                                                      color: Colors.grey[400],
                                                      size: 48,
                                                    ),
                                                    SizedBox(height: 8),
                                                    Text(
                                                      'Зураг ачаалахад алдаа гарлаа',
                                                      style: GoogleFonts.inter(
                                                        color: Colors.grey[500],
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),

                                        // Optional: Add a refresh button if image fails to load
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              shape: BoxShape.circle,
                                            ),
                                            child: IconButton(
                                              icon: Icon(Icons.refresh, color: Colors.white, size: 20),
                                              onPressed: () {
                                                setState(() {}); // Force rebuild
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () {
                                    _showImageFullScreen(task.image!);
                                  },
                                  icon: Icon(Icons.fullscreen, size: 18),
                                  label: Text(
                                    'Дэлгэцээр харах',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Color(0xFF4ECDC4),
                                  ),
                                ),
                              ),
                            ],
                          ),

                        if (task.status == 'done' || task.status == 'verified')
                          SizedBox(height: 24),

                        if (task.status == 'done' || task.status == 'verified')
                          SizedBox(height: 24),

                        // Additional Information
                        if (task.remarks != null && task.remarks!.isNotEmpty)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Нэмэлт тайлбар:',
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
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  task.remarks!,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: Colors.blue[800],
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),

                        SizedBox(height: 40), // Extra padding at bottom
                      ],
                    ),
                  ),
                ),

                // Action buttons at bottom
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(color: Colors.grey[200]!, width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Assign button (only if user can assign)
                      if (_canAssignTasks())
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _fetchWorkers();
                              _showAssignWorkerDialog(task);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Color(0xFF4ECDC4),
                              padding: EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: BorderSide(color: Color(0xFF4ECDC4)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.person_add, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Хуваарилах',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      if (_canAssignTasks()) SizedBox(width: 12),

                      // Change Status button
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _showStatusChangeDialog(task);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFF4ECDC4),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.swap_horiz, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Төлөв өөрчлөх',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimelinessChip(Task task) {
    final label = task.timelinessLabel!;
    final isNegative = task.isOverdue || task.wasCompletedLate;
    final color = isNegative ? Color(0xFFE53935) : Color(0xFF43A047);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isNegative ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            size: 14,
            color: color,
          ),
          SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDueDateChip(Task task) {
    final overdue = task.isOverdue;
    final color = overdue ? Color(0xFFE53935) : Colors.grey[600]!;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: overdue ? color.withOpacity(0.08) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: overdue ? color.withOpacity(0.35) : Colors.grey[200]!,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today, size: 14, color: color),
          SizedBox(width: 6),
          Text(
            _formatDate(task.dueDate!),
            style: GoogleFonts.inter(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to build detail row
  Widget _buildDetailRow({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: color.withOpacity(0.7),
        ),
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

  // Method to show image in full screen
  void _showImageFullScreen(String imageUrl) {
    print('🖼️ Opening fullscreen image: $imageUrl');

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.all(0),
          child: Stack(
            children: [
              // Full screen image
              Container(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        color: Colors.black,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                    : null,
                                color: Colors.white,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Зураг ачаалж байна...',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      print('❌ Fullscreen image error: $error');
                      return Container(
                        color: Colors.black,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image,
                                color: Colors.white70,
                                size: 60,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Зураг ачаалахад алдаа гарлаа',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _showImageFullScreen(imageUrl); // Retry
                                },
                                child: Text('Дахин оролдох'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Close button
              Positioned(
                top: 40,
                right: 20,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),

              // URL indicator (for debugging)
              Positioned(
                top: 40,
                left: 20,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    imageUrl.substring(0, Math.min(30, imageUrl.length)) + '...',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _filterTasksByStatus(String status) {
    setState(() {
      _filteredTasks = _tasks.where((task) => task.status == status).toList();
      print('📊 Filtered ${_filteredTasks.length} tasks for status: $status');
    });
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

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 22),
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

  // Add logout functionality in AppBar
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Даалгаврын Менежер',
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
          if (_userRole != null)
            Text(
              '(${_getRoleLabel(_userRole!)})',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w500,
                fontSize: 11,
                color: Colors.grey[500],
              ),
            ),
        ],
      ),
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      actions: [
        // Мэдэгдлийн icon
        Stack(
          children: [
            IconButton(
              icon: Icon(
                Icons.notifications_outlined,
                color: Colors.grey[700],
                size: 24,
              ),
              onPressed: _openNotificationScreen,
              tooltip: 'Мэдэгдэл',
            ),
            if (_unreadNotificationCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    _unreadNotificationCount > 99
                        ? '99+'
                        : _unreadNotificationCount.toString(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
        // Logout button
        IconButton(
          icon: Icon(
            Icons.logout,
            color: Colors.grey[700],
            size: 24,
          ),
          onPressed: () {
            _showLogoutConfirmationDialog();
          },
          tooltip: 'Гарах',
        ),
      ],
      bottom: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorColor: Color(0xFF4ECDC4),
        indicatorWeight: 3,
        indicatorPadding: EdgeInsets.symmetric(horizontal: 16),
        labelColor: Colors.grey[800],
        unselectedLabelColor: Colors.grey[500],
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13),
        tabs: _statusTabs.map((status) => Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _statusColors[status],
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 8),
              Text(_getStatusLabel(status)),
            ],
          ),
        )).toList(),
      ),
    );
  }

  void _showLogoutConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Гарах',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Та системээс гарахдаа итгэлтэй байна уу?',
            style: GoogleFonts.inter(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Үгүй',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _performLogout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFEF476F),
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Тийм',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performLogout() async {
    try {
      await auth.AuthService.clearSessionPreferences();

      // Navigate back to login screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => auth.LoginScreen()),
      );
    } catch (e) {
      print('❌ Logout error: $e');
      _showErrorSnackBar('Гарахад алдаа гарлаа');
    }
  }

  Future<void> _changeTaskStatus(Task task, String newStatus) async {
    if (newStatus == 'cancelled' && !_canCancelTasks()) {
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
      // Get token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        Navigator.of(context).pop();
        _showErrorSnackBar('Нэвтрэх эрх шаардлагатай');
        return;
      }

      print('🔄 Updating task status without image...');
      print('🎯 Task ID: $taskId, Status: $newStatus');

      // Changed from PATCH to POST and use query parameters
      final url = Uri.parse('${Url.url}/api/task/$taskId/status?status=$newStatus');
      print('🔗 URL: $url');

      // Use POST instead of PATCH
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        // Since we're using query parameters, we can send empty body
        // OR send JSON body if backend expects it
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

      // SOLUTION: Send status as query parameter instead of form field
      final url = Uri.parse('${Url.url}/api/task/$taskId/status?status=$newStatus');
      var request = http.MultipartRequest('POST', url);

      request.headers['Authorization'] = 'Bearer $token';

      // IMPORTANT: Don't add status to fields when using query params
      // request.fields['status'] = newStatus; // REMOVE THIS LINE

      var imageBytes = await image.readAsBytes();
      var multipartFile = http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: 'task_${taskId}.jpg',
        contentType: MediaType('image', 'jpeg'),
      );
      request.files.add(multipartFile);

      print('📤 Sending:');
      print('   URL with query: $url');
      print('   File field: image');
      print('   File size: ${imageBytes.length} bytes');

      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var jsonResponse = json.decode(responseData);

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: $responseData');

      Navigator.of(context).pop();

      if (response.statusCode == 200 && jsonResponse['success'] == true) {
        _showSuccessSnackBar('Төлөв амжилттай шинэчлэгдлээ 🎉');
        await _fetchTasks();
      } else {
        final errorMessage = jsonResponse['message'] ?? 'Алдаа гарлаа';
        _showErrorSnackBar(errorMessage);
      }
    } catch (e) {
      print('❌ Error: $e');
      Navigator.of(context).pop();
      _showErrorSnackBar('Алдаа гарлаа: $e');
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending': return 'Хүлээгдэж байна';
      case 'in_progress': return 'Хийгдэж байна';
      case 'done': return 'Дууссан';
      case 'verified': return 'Баталгаажсан';
      case 'cancelled': return 'Цуцлагдсан';
      default: return status;
    }
  }

  String _getRoleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'worker': return 'Ажилтан';
      case 'general_manager': return 'Ерөнхий менежер';
      case 'director': return 'Захирал';
      case 'supervisor': return 'Ахлах';
      case 'manager': return 'Менежер';
      case 'admin': return 'Админ';
      default: return role;
    }
  }

  // Enhanced date formatting method
  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  // More detailed date formatting for task details
  String _formatDetailedDate(dynamic dateValue) {
    try {
      DateTime date;

      if (dateValue == null) return 'Тодорхойгүй';

      if (dateValue is String) {
        date = DateTime.parse(dateValue);
      } else if (dateValue is DateTime) {
        date = dateValue;
      } else if (dateValue is int) {
        date = DateTime.fromMillisecondsSinceEpoch(dateValue);
      } else {
        return 'Тодорхойгүй';
      }

      final now = DateTime.now();
      final difference = now.difference(date);

      String timeAgo = '';
      if (difference.inDays > 365) {
        timeAgo = '${(difference.inDays / 365).floor()} жилийн өмнө';
      } else if (difference.inDays > 30) {
        timeAgo = '${(difference.inDays / 30).floor()} сарын өмнө';
      } else if (difference.inDays > 0) {
        timeAgo = '${difference.inDays} өдрийн өмнө';
      } else if (difference.inHours > 0) {
        timeAgo = '${difference.inHours} цагийн өмнө';
      } else if (difference.inMinutes > 0) {
        timeAgo = '${difference.inMinutes} минутын өмнө';
      } else {
        timeAgo = 'Саяхан';
      }

      final formattedDate = DateFormat('yyyy-MM-dd HH:mm').format(date);
      return '$formattedDate ($timeAgo)';
    } catch (e) {
      print('❌ Error formatting date: $dateValue, error: $e');
      return 'Тодорхойгүй';
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(),
      body: _isLoading
          ? _buildLoadingState()
          : RefreshIndicator(
        onRefresh: _fetchTasks,
        color: Color(0xFF4ECDC4),
        backgroundColor: Colors.white,
        displacement: 40,
        child: _filteredTasks.isEmpty
            ? _buildEmptyState()
            : _buildTaskList(),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
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
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.assignment_outlined,
              size: 48,
              color: Colors.grey[400],
            ),
          ),
          SizedBox(height: 24),
          Text(
            'Даалгавар олдсонгүй',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Энэ төлөвт даалгавар байхгүй байна',
            style: GoogleFonts.inter(
              color: Colors.grey[500],
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: _fetchTasks,
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF4ECDC4),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Дахин ачаалах',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList() {
    return ListView.separated(
      padding: EdgeInsets.all(16),
      itemCount: _filteredTasks.length,
      separatorBuilder: (context, index) => SizedBox(height: 16),
      itemBuilder: (context, index) {
        final task = _filteredTasks[index];
        return _buildTaskCard(task);
      },
    );
  }

  Widget _buildTaskCard(Task task) {
    final canAssign = _canAssignTasks();
    final creatorSupervisor = _taskCreatorSupervisorLabel(task);
    final workerAssignees = _workerAssigneesLabel(task);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        border: task.isOverdue
            ? Border.all(color: Color(0xFFE53935).withOpacity(0.45), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: task.isOverdue
                ? Color(0xFFE53935).withOpacity(0.08)
                : Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // Show task detail modal
            _showTaskDetailModal(task);
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with title and status
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

                // Priority and due date chips
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
                    if (task.dueDate != null) _buildDueDateChip(task),
                    if (task.timelinessLabel != null) _buildTimelinessChip(task),
                  ],
                ),
                if (creatorSupervisor != null) ...[
                  SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.assignment_ind_outlined, size: 16, color: Colors.teal[700]),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Даалгаварласан',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.teal[800],
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              creatorSupervisor,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.grey[800],
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                if (workerAssignees != null) ...[
                  SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.person_outline, size: 16, color: Colors.blueGrey[600]),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Гүйцэтгэгч ажилтан',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.blueGrey[700],
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              workerAssignees.replaceAll('\n', ' · '),
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.grey[800],
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                SizedBox(height: 16),

                // Divider
                Divider(height: 1, color: Colors.grey[100]),
                SizedBox(height: 14),

                // Footer with action buttons - Conditionally show Хуваарилах button
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Хуваарилах button - Only show if user has permission
                    if (canAssign)
                      OutlinedButton(
                        onPressed: () {
                          _fetchWorkers();
                          _showAssignWorkerDialog(task);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Color(0xFF4ECDC4),
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Color(0xFF4ECDC4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_add_alt_1, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Хуваарилах',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Add spacing only if both buttons are shown
                    if (canAssign) SizedBox(width: 12),

                    // Төлөв өөрчлөх button - Always show for all users
                    ElevatedButton(
                      onPressed: () => _showStatusChangeDialog(task),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF4ECDC4),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                        shadowColor: Colors.transparent,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swap_horiz, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Төлөв өөрчлөх',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
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

  void _showStatusChangeDialog(Task task) {
    final role = (_userRole ?? '').toLowerCase();
    final canVerify = role == 'supervisor' && task.status == 'done';
    final availableStatuses = _statusTabs.where((status) {
      if (status == task.status) return false;
      if (status == 'verified') return canVerify;
      if (status == 'cancelled') return _canCancelTasks();
      return true;
    }).toList();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 8,
          child: Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Төлөв өөрчлөх',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[800],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '"${task.title}" даалгаврын төлөв',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: Colors.grey[600],
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),

                // Show warning for "done" status
                if (availableStatuses.contains('done'))
                  Container(
                    margin: EdgeInsets.symmetric(vertical: 12),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Color(0xFFFFF3CD),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Color(0xFFFFEEBA)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info, color: Color(0xFF856404), size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '"Дууссан" төлөв рүү шилжихэд зураг шаардлагатай',
                            style: GoogleFonts.inter(
                              color: Color(0xFF856404),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                SizedBox(height: 8),
                ...availableStatuses.map((status) => Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      leading: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: _statusColors[status],
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(
                        _getStatusLabel(status),
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: status == 'done'
                          ? Text(
                        'Зураг шаардлагатай',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      )
                          : null,
                      tileColor: Colors.grey[50],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        _changeTaskStatus(task, status);
                      },
                    ),
                  ),
                )).toList(),
                SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[600],
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: Colors.grey[300]!),
                  ),
                  child: Text(
                    'Цуцлах',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _foregroundPushSub?.cancel();
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    super.dispose();
  }
}