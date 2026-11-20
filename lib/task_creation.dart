// task_creation.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskmanager/color/color.dart';
import 'package:taskmanager/login.dart' as auth;

class TaskCreationScreen extends StatefulWidget {
  @override
  _TaskCreationScreenState createState() => _TaskCreationScreenState();
}

class _TaskCreationScreenState extends State<TaskCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _selectedPriority = 'normal';
  List<int> _selectedAssignedTo = [];
  DateTime? _selectedDate;

  /// Users who can be assigned this task (workers under a supervisor, or leadership roles for others).
  List<auth.User> _assignableUsers = [];
  bool _isLoading = false;
  bool _isLoadingUsers = false;
  String? _userRole;
  bool _canCreateTasks = false;
  int? _currentUserId; // Add current user ID

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _checkUserRoleAndId();
    await _fetchUsers();
  }

  Future<void> _checkUserRoleAndId() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('role');
    final userId = prefs.getInt('userId');

    setState(() {
      _userRole = role;
      _currentUserId = userId;
      // Define which roles can create tasks
      final allowedRoles = ['supervisor', 'manager', 'admin', 'director', 'general_manager'];
      _canCreateTasks = role != null && allowedRoles.contains(role.toLowerCase());
    });
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _isLoadingUsers = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final role = prefs.getString('role')?.toLowerCase();
      final userId = prefs.getInt('userId');

      if (token == null) {
        throw Exception('Нэвтрэх эрх шаардлагатай');
      }

      if (role == 'supervisor' && userId != null) {
        final allWorkers = await auth.AuthService.getWorkers();
        _assignableUsers = allWorkers
            .where((w) =>
                w.role.toLowerCase() == 'worker' &&
                w.supervisor_id.contains(userId))
            .toList()
          ..sort((a, b) => a.full_name.compareTo(b.full_name));
      } else {
        final response = await http.get(
          Uri.parse('${Url.url}/api/user'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );

        if (response.statusCode == 200) {
          final jsonResponse = json.decode(response.body);
          final usersJson = jsonResponse['data'];

          if (usersJson is List) {
            final allUsers =
                usersJson.map((userJson) => auth.User.fromJson(userJson)).toList();

            _assignableUsers = allUsers
                .where((user) =>
                    user.role.toLowerCase() == 'supervisor' ||
                    user.role.toLowerCase() == 'manager' ||
                    user.role.toLowerCase() == 'admin')
                .toList()
              ..sort((a, b) => a.full_name.compareTo(b.full_name));
          }
        }
      }
    } catch (e) {
      _showErrorSnackBar('Хэрэглэгчийн мэдээлэл ачааллахад алдаа гарлаа');
    } finally {
      setState(() {
        _isLoadingUsers = false;
      });
    }
  }


  Future<void> _createTask() async {
    if (!_canCreateTasks) {
      _showErrorDialog('Таны эрх хүрэхгүй байна');
      return;
    }

    if (_formKey.currentState!.validate()) {
      if (_selectedDate == null) {
        _showErrorSnackBar('Дуусах хугацаа сонгоно уу');
        return;
      }



      setState(() {
        _isLoading = true;
      });

      try {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token');
        final userId = prefs.getInt('userId');

        if (token == null || userId == null) {
          throw Exception('Нэвтрэх эрх шаардлагатай');
        }

        final taskData = <String, dynamic>{
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim(),
          'priority': _selectedPriority,
          'status': 'pending',
          'created_by': userId,
          'frequency_type': 'none',
          'frequency_value': null,
          'assigned_to': _selectedAssignedTo.isNotEmpty ? _selectedAssignedTo : null,
          // Web админтай ижил: гүйцэтгэгчдийн ID-г supervisor_id-д ч оруулна
          'supervisor_id':
              _selectedAssignedTo.isNotEmpty ? _selectedAssignedTo : null,
          'due_date': _selectedDate!.toIso8601String(),
        };

        final response = await http.post(
          Uri.parse('${Url.url}/api/task'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode(taskData),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          _showSuccessSnackBar('Даалгавар амжилттай үүслээ 🎉');
          _resetForm();
        } else {
          final errorData = json.decode(response.body);
          throw Exception(errorData['message'] ?? 'Даалгавар үүсгэхэд алдаа гарлаа');
        }
      } catch (e) {
        _showErrorSnackBar('Алдаа гарлаа: $e');
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _resetForm() {
    _titleController.clear();
    _descriptionController.clear();
    _selectedPriority = 'normal';
    _selectedAssignedTo = [];
    _selectedDate = null;
    _formKey.currentState?.reset();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
      helpText: 'Дуусах огноо сонгох',
      cancelText: 'Цуцлах',
      confirmText: 'Сонгох',
      fieldLabelText: 'Дуусах огноо',
      fieldHintText: 'Огноо сонгоно уу',
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Эрх хүрэхгүй'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildPermissionDeniedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          SizedBox(height: 20),
          Text(
            'Эрх хүрэхгүй',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          SizedBox(height: 12),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Таны эрхээр даалгавар үүсгэх боломжгүй байна. Зөвхөн удирдлагад эрхтэй хэрэглэгчид даалгавар үүсгэх боломжтой.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Таны эрх: ${_userRole ?? "Тодорхойгүй"}',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Шинэ даалгавар үүсгэх'),
        centerTitle: true,
        actions: [
          if (_userRole != null)
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _canCreateTasks
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _canCreateTasks ? Colors.green : Colors.orange,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    _userRole!.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _canCreateTasks ? Colors.green : Colors.orange,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _canCreateTasks
          ? _buildTaskCreationForm()
          : _buildPermissionDeniedView(),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (subtitle != null) ...[
              SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).hintColor,
                    ),
              ),
            ],
            SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  /// Гүйцэтгэгчдийн жагсаалт — дотоод scroll байхгүй, бүхэл дэлгэцийн scroll-т орно.
  Widget _buildAssigneeList() {
    if (_isLoadingUsers) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_assignableUsers.isEmpty) {
      final isSupervisor = _userRole?.toLowerCase() == 'supervisor';
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          isSupervisor
              ? 'Таны харъяанд бүртгэлтэй ажилчин олдсонгүй.\nАдминаар ажилчдыг танд холбосон эсэхийг шалгана уу.'
              : 'Supervisor / manager хэрэглэгч олдсонгүй.\nСүлжээ, эрхээ шалгана уу.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in _assignableUsers.asMap().entries) ...[
          if (e.key > 0) Divider(height: 1),
          CheckboxListTile(
            title: Text(e.value.full_name),
            subtitle: Text('${e.value.role} · ID ${e.value.id}'),
            value: _selectedAssignedTo.contains(e.value.id),
            onChanged: (checked) {
              setState(() {
                final id = e.value.id;
                if (checked == true) {
                  if (!_selectedAssignedTo.contains(id)) {
                    _selectedAssignedTo.add(id);
                  }
                } else {
                  _selectedAssignedTo.remove(id);
                }
              });
            },
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ],
    );
  }

  Widget _buildTaskCreationForm() {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionCard(
                context: context,
                title: 'Үндсэн мэдээлэл',
                subtitle: 'Гарчиг, тайлбар, чухалчлал',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'Гарчиг *',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        filled: true,
                        prefixIcon: Icon(Icons.title_outlined),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Гарчиг оруулна уу';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 12),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        labelText: 'Тайлбар',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        filled: true,
                        prefixIcon: Icon(Icons.notes_outlined),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 4,
                      validator: (value) {
                        if (value != null && value.length > 500) {
                          return 'Тайлбар 500 тэмдэгтээс бага байх ёстой';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedPriority,
                      decoration: InputDecoration(
                        labelText: 'Чухалчлал',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        filled: true,
                        prefixIcon: Icon(Icons.flag_outlined),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'low',
                          child: Row(
                            children: [
                              Icon(Icons.circle, color: Colors.green, size: 12),
                              SizedBox(width: 8),
                              Text('Бага'),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'normal',
                          child: Row(
                            children: [
                              Icon(Icons.circle, color: Colors.blue, size: 12),
                              SizedBox(width: 8),
                              Text('Хэвийн'),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'high',
                          child: Row(
                            children: [
                              Icon(Icons.circle, color: Colors.red, size: 12),
                              SizedBox(width: 8),
                              Text('Өндөр'),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedPriority = value!;
                        });
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              _buildSectionCard(
                context: context,
                title: 'Хэрэгжүүлэгчид',
                subtitle: _userRole?.toLowerCase() == 'supervisor'
                    ? 'Таны харъяат ажилчид — олон хүн сонгож болно (${_selectedAssignedTo.length} сонгогдсон)'
                    : 'Даалгаврыг хэн гүйцэтгэх вэ? Олон хүн сонгож болно (${_selectedAssignedTo.length} сонгогдсон)',
                child: _buildAssigneeList(),
              ),
              SizedBox(height: 12),
              _buildSectionCard(
                context: context,
                title: 'Дуусах хугацаа',
                subtitle: 'Нэг удаагийн даалгавар',
                child: Material(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () => _selectDate(context),
                    borderRadius: BorderRadius.circular(10),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Огноо *',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        filled: true,
                        prefixIcon: Icon(Icons.event_outlined),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _selectedDate != null
                                ? '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}'
                                : 'Товшоод сонгоно уу',
                            style: TextStyle(
                              color: _selectedDate != null
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          Icon(Icons.expand_more, color: scheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_userRole?.toLowerCase() == 'supervisor')
                Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Material(
                    color: scheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, color: scheme.primary, size: 22),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Таны ID: $_currentUserId. Өөрийн харъяалагдах ажилчдад даалгавар өгөх боломжтой.',
                              style: TextStyle(
                                color: scheme.onPrimaryContainer,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              SizedBox(height: 24),
              FilledButton(
                onPressed: _isLoading ? null : _createTask,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isLoading
                    ? SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : Text(
                        'Даалгавар үүсгэх',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
              SizedBox(height: 10),
              OutlinedButton(
                onPressed: _isLoading ? null : _resetForm,
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text('Цэвэрлэх'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}