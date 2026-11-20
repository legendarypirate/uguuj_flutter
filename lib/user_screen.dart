// user_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskmanager/color/color.dart';

class UserScreen extends StatefulWidget {
  @override
  _UserScreenState createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  List<User> _users = [];
  User? _editingUser;
  bool _showForm = false;
  bool _loading = false;
  bool _formLoading = false;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Form controllers
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _selectedRole = 'worker';
  int? _selectedSupervisorId;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _loading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        _showErrorSnackBar('Нэвтрэх эрх шаардлагатай');
        return;
      }

      final response = await http.get(
        Uri.parse('${Url.url}/api/user'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        final List<dynamic> usersJson = jsonResponse['data'] ?? [];

        setState(() {
          _users = usersJson.map((json) => User.fromJson(json)).toList();
        });
        print('✅ Loaded ${_users.length} users');
      } else {
        _showErrorSnackBar('Хэрэглэгчдийг ачааллахад алдаа гарлаа: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching users: $e');
      _showErrorSnackBar('Хэрэглэгчдийг ачааллахад алдаа гарлаа');
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _addUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _formLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        _showErrorSnackBar('Нэвтрэх эрх шаардлагатай');
        return;
      }

      final userData = {
        'full_name': _fullNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'password': _passwordController.text,
        'role': _selectedRole,
        'supervisor_id': _selectedSupervisorId != null ? [_selectedSupervisorId] : [],
      };

      print('📤 Adding user with data: $userData');

      final response = await http.post(
        Uri.parse('${Url.url}/api/auth/register'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(userData),
      );

      final result = json.decode(response.body);
      print('📥 Response: ${response.statusCode}, ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        _showSuccessSnackBar('Хэрэглэгч амжилттай бүртгэгдлээ');
        _closeForm();
        await _fetchUsers();
      } else {
        _showErrorSnackBar(result['message'] ?? 'Хэрэглэгч бүртгэхэд алдаа гарлаа');
      }
    } catch (e) {
      print('❌ Error adding user: $e');
      _showErrorSnackBar('Хэрэглэгч бүртгэхэд алдаа гарлаа');
    } finally {
      setState(() {
        _formLoading = false;
      });
    }
  }

  Future<void> _editUser() async {
    if (!_formKey.currentState!.validate() || _editingUser == null) return;

    setState(() {
      _formLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        _showErrorSnackBar('Нэвтрэх эрх шаардлагатай');
        return;
      }

      final userData = {
        'full_name': _fullNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'role': _selectedRole,
        'supervisor_id': _selectedSupervisorId != null ? [_selectedSupervisorId] : [],
        'is_active': _editingUser!.isActive,
      };

      // Add password only if it's not empty
      if (_passwordController.text.isNotEmpty) {
        userData['password'] = _passwordController.text;
      }

      print('📤 Editing user ${_editingUser!.id} with data: $userData');

      final response = await http.put(
        Uri.parse('${Url.url}/api/user/${_editingUser!.id}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(userData),
      );

      final result = json.decode(response.body);
      print('📥 Response: ${response.statusCode}, ${response.body}');

      if (response.statusCode == 200) {
        _showSuccessSnackBar('Хэрэглэгч амжилттай шинэчлэгдлээ');
        _closeForm();
        await _fetchUsers();
      } else {
        _showErrorSnackBar(result['message'] ?? 'Хэрэглэгч шинэчлэхэд алдаа гарлаа');
      }
    } catch (e) {
      print('❌ Error editing user: $e');
      _showErrorSnackBar('Хэрэглэгч шинэчлэхэд алдаа гарлаа');
    } finally {
      setState(() {
        _formLoading = false;
      });
    }
  }

  Future<void> _deleteUser(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('Хэрэглэгч устгах'),
          ],
        ),
        content: Text('Та энэ хэрэглэгчийг устгахдаа итгэлтэй байна уу?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Үгүй'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Тийм, устга'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        _showErrorSnackBar('Нэвтрэх эрх шаардлагатай');
        return;
      }

      final response = await http.delete(
        Uri.parse('${Url.url}/api/user/$id'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        _showSuccessSnackBar('Хэрэглэгч амжилттай устгагдлаа');
        await _fetchUsers();
      } else {
        _showErrorSnackBar('Хэрэглэгч устгахад алдаа гарлаа');
      }
    } catch (e) {
      print('❌ Error deleting user: $e');
      _showErrorSnackBar('Хэрэглэгч устгахад алдаа гарлаа');
    }
  }

  Future<void> _toggleUserStatus(int id, bool currentStatus) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        _showErrorSnackBar('Нэвтрэх эрх шаардлагатай');
        return;
      }

      final response = await http.patch(
        Uri.parse('${Url.url}/api/user/$id/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'is_active': !currentStatus}),
      );

      if (response.statusCode == 200) {
        _showSuccessSnackBar(
          'Хэрэглэгч ${!currentStatus ? 'идэвхтэй' : 'идэвхгүй'} боллоо',
        );
        await _fetchUsers();
      } else {
        _showErrorSnackBar('Хэрэглэгчийн статус өөрчлөхөд алдаа гарлаа');
      }
    } catch (e) {
      print('❌ Error toggling user status: $e');
      _showErrorSnackBar('Хэрэглэгчийн статус өөрчлөхөд алдаа гарлаа');
    }
  }

  void _openFormForEdit(User user) {
    setState(() {
      _editingUser = user;
      _fullNameController.text = user.fullName;
      _phoneController.text = user.phone;
      _passwordController.clear();
      _selectedRole = user.role;
      _selectedSupervisorId = user.supervisorId.isNotEmpty ? user.supervisorId.first : null;
      _showForm = true;
    });
  }

  void _openFormForAdd() {
    setState(() {
      _editingUser = null;
      _fullNameController.clear();
      _phoneController.clear();
      _passwordController.clear();
      _selectedRole = 'worker';
      _selectedSupervisorId = null;
      _showForm = true;
    });
  }

  void _closeForm() {
    setState(() {
      _showForm = false;
      _editingUser = null;
      _formKey.currentState?.reset();
    });
  }

  List<User> _getPotentialSupervisors() {
    return _users.where((user) {
      if (_editingUser != null && user.id == _editingUser!.id) return false;
      if (!user.isActive) return false;
      if (user.role != 'supervisor') return false;
      return true;
    }).toList();
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Хэрэглэгчийн Удирдлага'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Main content
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: _openFormForAdd,
                    icon: Icon(Icons.person_add, size: 20),
                    label: Text('Шинэ хэрэглэгч'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                SizedBox(height: 20),

                // Users table
                Expanded(
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _loading && _users.isEmpty
                        ? Center(child: CircularProgressIndicator())
                        : _users.isEmpty
                        ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
                          SizedBox(height: 16),
                          Text(
                            'Хэрэглэгч олдсонгүй',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                        : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Container(
                        constraints: BoxConstraints(
                          minWidth: MediaQuery.of(context).size.width - 32,
                        ),
                        child: DataTable(
                          columnSpacing: 16,
                          horizontalMargin: 12,
                          headingRowHeight: 50,
                          dataRowHeight: 60,
                          columns: [
                            DataColumn(label: Text('Нэр', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Утас', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Эрх', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Ахлах', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Статус', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Үйлдэл', style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: _users.map((user) {
                            final supervisorName = user.supervisor != null
                                ? user.supervisor!['full_name']
                                : (user.supervisorId.isNotEmpty
                                ? user.supervisorId.map((sid) => _users.firstWhere(
                                  (u) => u.id == sid,
                              orElse: () => User(
                                id: 0,
                                fullName: 'ID:$sid',
                                phone: '',
                                role: '',
                                isActive: false,
                              ),
                            ).fullName).join(', ')
                                : 'Байхгүй');

                            return DataRow(cells: [
                              DataCell(Container(
                                width: 120,
                                child: Text(
                                  user.fullName,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 14),
                                ),
                              )),
                              DataCell(Container(
                                width: 100,
                                child: Text(
                                  user.phone,
                                  style: TextStyle(fontSize: 14),
                                ),
                              )),
                              DataCell(
                                Container(
                                  width: 100,
                                  child: Chip(
                                    label: Text(
                                      _getRoleLabel(user.role),
                                      style: TextStyle(fontSize: 11),
                                    ),
                                    backgroundColor: _getRoleColor(user.role),
                                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  ),
                                ),
                              ),
                              DataCell(Container(
                                width: 100,
                                child: Text(
                                  supervisorName,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13),
                                ),
                              )),
                              DataCell(
                                Switch(
                                  value: user.isActive,
                                  onChanged: (value) {
                                    _toggleUserStatus(user.id, user.isActive);
                                  },
                                  activeColor: Colors.green,
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.edit, size: 20, color: Colors.blue),
                                      onPressed: () => _openFormForEdit(user),
                                      tooltip: 'Засах',
                                      padding: EdgeInsets.zero,
                                      constraints: BoxConstraints(),
                                    ),
                                    SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(Icons.delete, size: 20, color: Colors.red),
                                      onPressed: () => _deleteUser(user.id),
                                      tooltip: 'Устгах',
                                      padding: EdgeInsets.zero,
                                      constraints: BoxConstraints(),
                                    ),
                                  ],
                                ),
                              ),
                            ]);
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Form drawer
          if (_showForm)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                constraints: BoxConstraints(maxWidth: 400),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 10,
                      offset: Offset(-3, 0),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Header
                      Container(
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
                          color: Colors.grey[50],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _editingUser != null ? 'Хэрэглэгч засах' : 'Шинэ хэрэглэгч',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  _editingUser != null
                                      ? 'Хэрэглэгчийн мэдээлэл шинэчлэх'
                                      : 'Шинэ хэрэглэгч бүртгэх',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: Icon(Icons.close, size: 24),
                              onPressed: _closeForm,
                              color: Colors.grey[600],
                            ),
                          ],
                        ),
                      ),

                      // Form content
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Full Name
                              TextFormField(
                                controller: _fullNameController,
                                decoration: InputDecoration(
                                  labelText: 'Бүтэн нэр *',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  prefixIcon: Icon(Icons.person),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Бүтэн нэр оруулна уу';
                                  }
                                  return null;
                                },
                              ),
                              SizedBox(height: 16),

                              // Phone
                              TextFormField(
                                controller: _phoneController,
                                decoration: InputDecoration(
                                  labelText: 'Утасны дугаар *',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  prefixIcon: Icon(Icons.phone),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                ),
                                keyboardType: TextInputType.phone,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Утасны дугаар оруулна уу';
                                  }
                                  return null;
                                },
                              ),
                              SizedBox(height: 16),

                              // Password
                              TextFormField(
                                controller: _passwordController,
                                decoration: InputDecoration(
                                  labelText: _editingUser != null
                                      ? 'Нууц үг (өөрчлөхгүй бол хоосон үлдээнэ)'
                                      : 'Нууц үг *',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  prefixIcon: Icon(Icons.lock),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                ),
                                obscureText: true,
                                validator: (value) {
                                  if (_editingUser == null && (value == null || value.isEmpty)) {
                                    return 'Нууц үг оруулна уу';
                                  }
                                  return null;
                                },
                              ),
                              SizedBox(height: 16),

                              // Role
                              DropdownButtonFormField<String>(
                                value: _selectedRole,
                                decoration: InputDecoration(
                                  labelText: 'Эрх *',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  prefixIcon: Icon(Icons.verified_user),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'worker',
                                    child: Text('Ажилтан'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'supervisor',
                                    child: Text('Ахлах'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'general_manager',
                                    child: Text('Ерөнхий менежер'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'director',
                                    child: Text('Захирал'),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _selectedRole = value!;
                                  });
                                },
                              ),
                              SizedBox(height: 16),

                              // Supervisor
                              DropdownButtonFormField<int?>(
                                value: _selectedSupervisorId,
                                decoration: InputDecoration(
                                  labelText: 'Ахлах',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  prefixIcon: Icon(Icons.supervised_user_circle),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: null,
                                    child: Text('Ахлахгүй'),
                                  ),
                                  ..._getPotentialSupervisors().map((supervisor) {
                                    return DropdownMenuItem(
                                      value: supervisor.id,
                                      child: Text('${supervisor.fullName} (${_getRoleLabel(supervisor.role)})'),
                                    );
                                  }).toList(),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _selectedSupervisorId = value;
                                  });
                                },
                              ),
                              SizedBox(height: 32),

                              // Form buttons
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _closeForm,
                                      style: OutlinedButton.styleFrom(
                                        padding: EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        side: BorderSide(color: Colors.grey[400]!),
                                      ),
                                      child: Text(
                                        'Цуцлах',
                                        style: TextStyle(color: Colors.grey[700]),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: _formLoading
                                          ? null
                                          : () {
                                        if (_editingUser != null) {
                                          _editUser();
                                        } else {
                                          _addUser();
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: _formLoading
                                          ? SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                          : Text(_editingUser != null ? 'Шинэчлэх' : 'Бүртгэх'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getRoleLabel(String role) {
    switch (role) {
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

  Color _getRoleColor(String role) {
    switch (role) {
      case 'director':
        return Colors.purple.withOpacity(0.2);
      case 'general_manager':
        return Colors.blue.withOpacity(0.2);
      case 'supervisor':
        return Colors.green.withOpacity(0.2);
      case 'worker':
        return Colors.grey.withOpacity(0.2);
      default:
        return Colors.grey.withOpacity(0.2);
    }
  }
}

class User {
  final int id;
  final String fullName;
  final String phone;
  final String role;
  final List<int> supervisorId;
  final bool isActive;
  final Map<String, dynamic>? supervisor;

  User({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.role,
    this.supervisorId = const [],
    required this.isActive,
    this.supervisor,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final sup = <int>{};
    for (final key in ['supervisor_id', 'supervisor_ids']) {
      if (!json.containsKey(key)) continue;
      sup.addAll(_parseSupervisorId(json[key]));
    }
    return User(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      fullName: json['full_name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      supervisorId: sup.toList(),
      isActive: json['is_active'] is bool ? json['is_active'] : (json['is_active'] == 1 || json['is_active'] == true),
      supervisor: json['supervisor'] is Map<String, dynamic> ? json['supervisor'] : null,
    );
  }

  static List<int> _parseSupervisorId(dynamic value) {
    if (value == null) return [];
    if (value is int) return [value];
    if (value is num) return [value.toInt()];
    if (value is List) {
      return value
          .expand((e) => _parseSupervisorId(e))
          .where((id) => id > 0)
          .toList();
    }
    if (value is String) {
      final s = value.trim();
      if (s.isEmpty) return [];
      if (s.startsWith('[')) {
        try {
          final decoded = jsonDecode(s);
          return _parseSupervisorId(decoded);
        } catch (_) {}
      }
      return s
          .split(RegExp(r'[,\s]+'))
          .map((p) => int.tryParse(p.trim()) ?? 0)
          .where((id) => id > 0)
          .toList();
    }
    return [];
  }
}