// bottom_nav.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskmanager/report.dart';
import 'package:taskmanager/tasklist.dart';
import 'package:taskmanager/recurring_tasks_screen.dart';
import 'package:taskmanager/task_creation.dart';
import 'package:taskmanager/admin_screen.dart'; // Add admin screen

class BottomNavScreen extends StatefulWidget {
  @override
  _BottomNavScreenState createState() => _BottomNavScreenState();
}

class _BottomNavScreenState extends State<BottomNavScreen> {
  int _selectedIndex = 0;
  String? _userRole;
  bool _canCreateTasks = false;
  bool _canViewReports = false;
  bool _canAccessAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkUserRole();
  }

  Future<void> _checkUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('role');

    setState(() {
      _userRole = role;
      // Даалгавар үүсгэх эрх
      final allowedCreateRoles = ['supervisor', 'manager', 'admin', 'director', 'general_manager'];
      _canCreateTasks = role != null && allowedCreateRoles.contains(role.toLowerCase());

      // Тайлан үзэх эрх - зөвхөн supervisor болон дээрх role-ууд
      final allowedReportRoles = ['supervisor', 'manager', 'admin', 'director', 'general_manager'];
      _canViewReports = role != null && allowedReportRoles.contains(role.toLowerCase());

      // Админ цэс рүү хандах эрх - зөвхөн director болон general_manager
      final allowedAdminRoles = ['director', 'general_manager', 'admin'];
      _canAccessAdmin = role != null && allowedAdminRoles.contains(role.toLowerCase());

      // Хэрэглэгчийн эрх хязгаарлалт шалгах
      if (!_canCreateTasks && _selectedIndex == 2) {
        _selectedIndex = 0;
      }
      if (!_canViewReports && _selectedIndex == 3) {
        _selectedIndex = 0;
      }
      if (!_canAccessAdmin && _selectedIndex == 4) {
        _selectedIndex = 0;
      }
    });
  }

  List<Widget> _getWidgetOptions() {
    return <Widget>[
      TaskListScreen(), // Non-recurring tasks
      RecurringTasksScreen(), // Recurring tasks with calendar
      _canCreateTasks ? TaskCreationScreen() : _buildPermissionDeniedView('Даалгавар үүсгэх'),
      _canViewReports ? ReportScreen() : _buildPermissionDeniedView('Тайлан үзэх'),
      _canAccessAdmin ? AdminScreen() : _buildPermissionDeniedView('Админ хэсэг'),
    ];
  }

  Widget _buildPermissionDeniedView(String feature) {
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
          Text(
            'Таны эрхээр $feature боломжгүй',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
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
          SizedBox(height: 16),
          if (feature == 'Админ хэсэг')
            Text(
              'Зөвхөн Захирал, Ерөнхий менежер, Админ эрхтэй',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  List<BottomNavigationBarItem> _getBottomNavItems() {
    List<BottomNavigationBarItem> items = [
      const BottomNavigationBarItem(
        icon: Icon(Icons.list_alt),
        label: 'Даалгавар',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.calendar_today),
        label: 'Давтамжит',
      ),
    ];

    // Даалгавар үүсгэх цэс
    if (_canCreateTasks) {
      items.add(
        const BottomNavigationBarItem(
          icon: Icon(Icons.add_circle_outline),
          label: 'Шинэ',
        ),
      );
    } else {
      items.add(
        const BottomNavigationBarItem(
          icon: Icon(Icons.lock_outline),
          label: 'Шинэ',
        ),
      );
    }

    // Тайлан цэс
    if (_canViewReports) {
      items.add(
        const BottomNavigationBarItem(
          icon: Icon(Icons.assessment),
          label: 'Тайлан',
        ),
      );
    } else {
      items.add(
        const BottomNavigationBarItem(
          icon: Icon(Icons.lock_outline),
          label: 'Тайлан',
        ),
      );
    }

    // Админ цэс
    if (_canAccessAdmin) {
      items.add(
        const BottomNavigationBarItem(
          icon: Icon(Icons.admin_panel_settings),
          label: 'Админ',
        ),
      );
    } else {
      items.add(
        const BottomNavigationBarItem(
          icon: Icon(Icons.lock_outline),
          label: 'Админ',
        ),
      );
    }

    return items;
  }

  void _onItemTapped(int index) {
    // Эхний хоёр цэс рүү зөвшөөрөгдсөн (Даалгавар, Давтамжит)
    if (index == 0 || index == 1) {
      setState(() {
        _selectedIndex = index;
      });
      return;
    }

    // Даалгавар үүсгэх цэс
    if (index == 2 && !_canCreateTasks) {
      _showPermissionDialog(
        'Таны эрхээр даалгавар үүсгэх боломжгүй байна.',
        'Зөвхөн удирдлагад эрхтэй хэрэглэгчид даалгавар үүсгэх боломжтой.',
      );
      return;
    }

    // Тайлан цэс
    if (index == 3 && !_canViewReports) {
      _showPermissionDialog(
        'Таны эрхээр тайлан үзэх боломжгүй байна.',
        'Зөвхөн удирдлагад эрхтэй хэрэглэгчид тайлан үзэх боломжтой.',
      );
      return;
    }

    // Админ цэс
    if (index == 4 && !_canAccessAdmin) {
      _showPermissionDialog(
        'Таны эрхээр Админ хэсэгт нэвтрэх боломжгүй байна.',
        'Зөвхөн Захирал, Ерөнхий менежер, Админ эрхтэй хэрэглэгчид нэвтрэх боломжтой.',
      );
      return;
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  void _showPermissionDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.orange, size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: 14, // Smaller font size
                      color: Colors.grey[700],
                      height: 1.4,
                    ),
                  ),
                ),
                SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.person, size: 16, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        'Таны эрх: ',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                        ),
                      ),
                      Text(
                        _userRole?.toUpperCase() ?? "Тодорхойгүй",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue,
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    ),
                    child: Text(
                      'Хаах',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _getWidgetOptions().elementAt(_selectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: _getBottomNavItems(),
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}