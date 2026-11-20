// login.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskmanager/tasklist.dart';

import 'bottom_nav.dart';
import 'color/color.dart';
import 'push_service.dart';

/// Утас + нууц үг — гарахад устахгүй, дахин нэвтрэхэд ашиглана.
const String kPrefsSavedLoginPhone = 'saved_login_phone';
const String kPrefsSavedLoginPassword = 'saved_login_password';

class LoginCredentialsCache {
  static Future<void> save(String phoneDigits, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefsSavedLoginPhone, phoneDigits);
    await prefs.setString(kPrefsSavedLoginPassword, password);
  }

  static Future<Map<String, String>> read() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'phone': prefs.getString(kPrefsSavedLoginPhone) ?? '',
      'password': prefs.getString(kPrefsSavedLoginPassword) ?? '',
    };
  }
}

class LoginRequest {
  final String phone;
  final String password;

  LoginRequest({
    required this.phone,
    required this.password,
  });

  Map<String, dynamic> toJson() {
    return {
      'phone': phone,
      'password': password,
    };
  }
}

class LoginResponse {
  final String token;
  final User user;

  LoginResponse({
    required this.token,
    required this.user,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    try {
      print('🔄 Parsing LoginResponse from JSON: $json');

      // Validate token
      final token = json['token'];
      if (token is! String) {
        print('❌ Token is not String: $token (type: ${token.runtimeType})');
        throw FormatException('Token must be String, got ${token.runtimeType}');
      }

      // Validate user
      final userJson = json['user'];
      if (userJson is! Map<String, dynamic>) {
        print('❌ User is not Map: $userJson (type: ${userJson.runtimeType})');
        throw FormatException('User must be Map, got ${userJson.runtimeType}');
      }

      return LoginResponse(
        token: token,
        user: User.fromJson(userJson),
      );
    } catch (e) {
      print('❌ LoginResponse parsing error: $e');
      rethrow;
    }
  }
}

// login.dart - Update your User class
class User {
  final int id;
  final String full_name;
  final String phone;
  final String? email;
  final String role;
  final List<int> supervisor_id;
  final bool is_active;
  final String? createdAt;
  final String? updatedAt;

  User({
    required this.id,
    required this.full_name,
    required this.phone,
    this.email,
    required this.role,
    this.supervisor_id = const [],
    required this.is_active,
    this.createdAt,
    this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    /// Handles int, List, Postgres/JSON quirks, and comma-separated strings (e.g. "5,4").
    List<int> parseSupervisorId(dynamic value) {
      if (value == null) return [];
      if (value is int) return [value];
      if (value is num) return [value.toInt()];
      if (value is List) {
        return value
            .expand((e) => parseSupervisorId(e))
            .where((id) => id > 0)
            .toList();
      }
      if (value is String) {
        final s = value.trim();
        if (s.isEmpty) return [];
        if (s.startsWith('[')) {
          try {
            final decoded = jsonDecode(s);
            return parseSupervisorId(decoded);
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

    final supervisorIds = <int>{};
    for (final key in ['supervisor_id', 'supervisor_ids']) {
      if (!json.containsKey(key)) continue;
      supervisorIds.addAll(parseSupervisorId(json[key]));
    }

    return User(
      id: json['id'] ?? 0,
      full_name: json['full_name'] ?? '',
      phone: json['phone'] ?? '',
      email: json['email'],
      role: json['role'] ?? '',
      supervisor_id: supervisorIds.toList(),
      is_active: json['is_active'] ?? true,
      createdAt: json['createdAt'],
      updatedAt: json['updatedAt'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': full_name,
      'phone': phone,
      'email': email,
      'role': role,
      'supervisor_id': supervisor_id,
      'is_active': is_active,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

class AuthService {
  static const String baseUrl = Url.url+'/api';

  static Future<LoginResponse> loginWithPhone({
    required String phone,
    required String password,
  }) async {
    try {
      print('🔐 Login attempt with phone: $phone');

      final loginRequest = LoginRequest(
        phone: phone,
        password: password,
      );

      final requestBody = json.encode(loginRequest.toJson());
      print('📤 Request body: $requestBody');

      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: requestBody,
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        print('✅ Login successful, parsing response...');

        return LoginResponse.fromJson(jsonResponse);
      } else if (response.statusCode == 401) {
        throw Exception('Утасны дугаар эсвэл нууц үг буруу байна');
      } else if (response.statusCode == 404) {
        throw Exception('Хэрэглэгч олдсонгүй');
      } else {
        throw Exception('Нэвтрэхэд алдаа гарлаа: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ AuthService error: $e');
      print('❌ Error type: ${e.runtimeType}');
      print('❌ Stack trace: ${StackTrace.current}');
      throw Exception('Серверт холбогдоход алдаа гарлаа: $e');
    }
  }

  // Add this method to fetch workers (users with role 'worker')
// Update the getWorkers() method in login.dart:
  // Update the getWorkers() method in login.dart:
  static Future<List<User>> getWorkers() async {
    try {
      print('👥 Fetching workers from API...');

      // Get token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null || token.isEmpty) {
        print('❌ Token not found or empty in SharedPreferences');
        throw Exception('Authentication token not found. Please login again.');
      }

      print('🔐 Using token for authorization');

      final response = await http.get(
        Uri.parse('$baseUrl/user'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('📥 Users response status: ${response.statusCode}');
      print('📥 Users response body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);

        // Debug: Print the full response structure
        print('📊 Full response structure:');
        print('   - success: ${jsonResponse['success']}');
        print('   - has data key: ${jsonResponse.containsKey('data')}');
        print('   - data type: ${jsonResponse['data']?.runtimeType}');

        // Check if response has the expected structure
        if (jsonResponse['success'] != true) {
          print('❌ API returned success: false');
          throw Exception('API request was not successful');
        }

        final usersJson = jsonResponse['data'];

        if (usersJson == null) {
          print('❌ No data field in response');
          return [];
        }

        if (usersJson is! List) {
          print('❌ Data field is not a List, it is: ${usersJson.runtimeType}');
          return [];
        }

        print('👥 All users from API: ${usersJson.length}');
        for (var user in usersJson) {
          print('   - ${user['full_name']} (${user['role']})');
        }

        // Filter users with role 'worker'
        final workers = (usersJson as List<dynamic>)
            .where((userJson) =>
        userJson != null &&
            userJson is Map<String, dynamic> &&
            userJson['role'] != null &&
            userJson['role'].toString().toLowerCase() == 'worker')
            .map((userJson) => User.fromJson(userJson as Map<String, dynamic>))
            .toList();

        print('✅ Found ${workers.length} workers');

        if (workers.isEmpty) {
          print('⚠️ No workers found. Checking all available roles...');
          // List all available roles for debugging
          final allRoles = (usersJson as List<dynamic>)
              .where((userJson) => userJson != null && userJson is Map<String, dynamic>)
              .map((userJson) => userJson['role']?.toString())
              .where((role) => role != null)
              .toSet()
              .toList();
          print('   Available roles in system: $allRoles');
        }

        return workers;
      } else if (response.statusCode == 401) {
        print('❌ Unauthorized - Token might be invalid or expired');
        throw Exception('Authentication failed. Please login again.');
      } else if (response.statusCode == 403) {
        print('❌ Forbidden - User does not have permission to view users');
        throw Exception('You do not have permission to view users.');
      } else {
        print('❌ Failed to fetch users: ${response.statusCode}');
        // Try to parse error message
        try {
          final errorJson = json.decode(response.body);
          final errorMsg = errorJson['message'] ?? errorJson['error'] ?? 'Unknown error';
          throw Exception('Failed to fetch workers: $errorMsg');
        } catch (_) {
          throw Exception('Failed to fetch workers: ${response.statusCode}');
        }
      }
    } catch (e) {
      print('❌ Error fetching workers: $e');
      print('❌ Stack trace: ${StackTrace.current}');

      // Provide more user-friendly error messages
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection refused')) {
        throw Exception('Серверт холбогдоход алдаа гарлаа. Сервер ажиллаж байгаа эсэхийг шалгана уу.');
      } else if (e.toString().contains('Authentication')) {
        throw Exception('Нэвтрэх эрх дууссан байна. Дахин нэвтрэнэ үү.');
      } else {
        throw Exception('Ажилчдын мэдээлэл авахад алдаа гарлаа: ${e.toString()}');
      }
    }
  }

  /// All users (any role) — for resolving assignee names on task cards.
  static Future<List<User>> fetchAllUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null || token.isEmpty) {
      throw Exception('Authentication token not found. Please login again.');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/user'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch users: ${response.statusCode}');
    }

    final jsonResponse = json.decode(response.body);
    if (jsonResponse['success'] != true) {
      throw Exception('API request was not successful');
    }

    final usersJson = jsonResponse['data'];
    if (usersJson == null || usersJson is! List) {
      return [];
    }

    return usersJson
        .whereType<Map<String, dynamic>>()
        .map((m) => User.fromJson(m))
        .toList();
  }

  /// Logout: session only. Утас/нууц (`saved_login_*`) хадгалагдана.
  static Future<void> clearSessionPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
    await prefs.remove('userName');
    await prefs.remove('phone');
    await prefs.remove('role');
    await prefs.remove('token');
    await prefs.remove('isLoggedIn');
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  // Add a FocusNode to manage keyboard
  final FocusNode _passwordFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final saved = await LoginCredentialsCache.read();
    if (!mounted) return;
    final p = saved['phone'] ?? '';
    final pw = saved['password'] ?? '';
    if (p.isNotEmpty) {
      _phoneController.text = p;
    }
    if (pw.isNotEmpty) {
      _passwordController.text = pw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Нэвтрэх'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Add some space at the top for better visual balance

                // Logo and title
                Image.asset('assets/logo.jpg', width: 150, height: 150),
                const SizedBox(height: 8),

                // Phone Number Field
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) {
                    FocusScope.of(context).requestFocus(_passwordFocusNode);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Утасны дугаар',
                    prefixText: '+976 ',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Утасны дугаараа оруулна уу';
                    }
                    final digitsOnly = value.replaceAll('+976 ', '');
                    if (digitsOnly.length != 8) {
                      return 'Утасны дугаар 8 оронтой байх ёстой';
                    }
                    if (!RegExp(r'^\d+$').hasMatch(digitsOnly)) {
                      return 'Зөвхөн тоо оруулна уу';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Password Field
                TextFormField(
                  controller: _passwordController,
                  focusNode: _passwordFocusNode,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) {
                    if (!_isLoading) {
                      _login();
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Нууц үг',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Нууц үгээ оруулна уу';
                    }
                    if (value.length < 6) {
                      return 'Нууц үг хамгийн багадаа 6 тэмдэгтээс бүрдэх ёстой';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                // Login Button
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      disabledBackgroundColor: Colors.blue.shade200,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                        : const Text(
                      'Нэвтрэх',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),

                // Add some padding at the bottom for better scrolling
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      // Dismiss keyboard before login
      FocusScope.of(context).unfocus();

      setState(() {
        _isLoading = true;
      });

      try {
        String phone = _phoneController.text.replaceAll('+976 ', '').trim();

        print('🚀 Starting login process...');
        print('📱 Phone: $phone');

        final response = await AuthService.loginWithPhone(
          phone: phone,
          password: _passwordController.text,
        );

        await LoginCredentialsCache.save(phone, _passwordController.text);

        // Save user data to SharedPreferences
        await _saveUserData(response);
        await PushService.registerTokenAfterLogin();

        print('🎯 Login successful! Navigating to TaskListScreen...');

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => BottomNavScreen(),
            ),
          );
        }

      } catch (e) {
        if (mounted) {
          print('💥 Login process error: $e');

          String errorMessage = e.toString();
          if (errorMessage.contains('Серверт холбогдоход алдаа гарлаа: ')) {
            errorMessage = errorMessage.replaceAll('Серверт холбогдоход алдаа гарлаа: ', '');
          }

          _showErrorDialog(errorMessage);
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _saveUserData(LoginResponse response) async {
    try {
      print('💾 Saving user data to SharedPreferences...');
      print('👤 User ID: ${response.user.id}');
      print('👤 Name: ${response.user.full_name}');
      print('👤 Role: ${response.user.role}');
      print('🔐 Token: ${response.token}');

      final prefs = await SharedPreferences.getInstance();

      // Save user data
      await prefs.setInt('userId', response.user.id);
      await prefs.setString('userName', response.user.full_name);
      await prefs.setString('phone', response.user.phone);
      await prefs.setString('role', response.user.role);
      await prefs.setString('token', response.token);
      await prefs.setBool('isLoggedIn', true);

      print('✅ User data saved successfully to SharedPreferences');

    } catch (e) {
      print('❌ Error saving user data: $e');
      rethrow;
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Алдаа'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }
}