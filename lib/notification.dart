import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:taskmanager/push_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskmanager/color/color.dart';

class AppNotification {
  final int id;
  final String title;
  final String message;
  final String type;
  final String priority;
  final String sender;
  final String receiverType;
  final DateTime sentAt;
  bool read;
  final String status;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.priority,
    required this.sender,
    required this.receiverType,
    required this.sentAt,
    required this.read,
    required this.status,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    DateTime sentAt = DateTime.now();
    final created = json['created_at']?.toString();
    if (created != null) {
      try {
        sentAt = DateTime.parse(created);
      } catch (_) {}
    }

    return AppNotification(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}') ?? 0,
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      type: json['type']?.toString() ?? 'announcement',
      priority: json['priority']?.toString() ?? 'medium',
      sender: json['sender_name']?.toString() ?? 'Систем',
      receiverType: json['receiver_type']?.toString() ?? 'system',
      sentAt: sentAt,
      read: json['read'] == true,
      status: 'sent',
    );
  }

  AppNotification copyWith({bool? read}) {
    return AppNotification(
      id: id,
      title: title,
      message: message,
      type: type,
      priority: priority,
      sender: sender,
      receiverType: receiverType,
      sentAt: sentAt,
      read: read ?? this.read,
      status: status,
    );
  }
}

class NotificationScreen extends StatefulWidget {
  @override
  _NotificationScreenState createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<AppNotification> notifications = [];
  bool _isLoading = true;
  String? _error;
  String? _userName;
  String? _userRole;
  StreamSubscription<RemoteMessage>? _foregroundPushSub;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _fetchNotifications();
    _foregroundPushSub = PushService.foregroundMessages.listen((_) {
      _fetchNotifications();
    });
  }

  @override
  void dispose() {
    _foregroundPushSub?.cancel();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userName = prefs.getString('userName');
      _userRole = prefs.getString('role');
    });
  }

  Future<Map<String, String>> _authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _fetchNotifications() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('${Url.url}/api/notifications/me'),
        headers: headers,
      );

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Нэвтрэх эрх шаардлагатай');
      }

      if (response.statusCode != 200) {
        final body = json.decode(response.body);
        throw Exception(body['message']?.toString() ?? 'Ачааллахад алдаа гарлаа');
      }

      final jsonResponse = json.decode(response.body);
      final rows = jsonResponse['data'] as List<dynamic>? ?? [];

      if (!mounted) return;
      setState(() {
        notifications = rows
            .map((row) => AppNotification.fromJson(row as Map<String, dynamic>))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  int get unreadCount => notifications.where((n) => !n.read).length;

  Future<void> _markAsRead(int id) async {
    try {
      final headers = await _authHeaders();
      await http.patch(
        Uri.parse('${Url.url}/api/notifications/$id/read'),
        headers: headers,
      );
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      final index = notifications.indexWhere((n) => n.id == id);
      if (index != -1) {
        notifications[index] = notifications[index].copyWith(read: true);
      }
    });
  }

  Future<void> _markAllAsRead() async {
    try {
      final headers = await _authHeaders();
      await http.patch(
        Uri.parse('${Url.url}/api/notifications/read-all'),
        headers: headers,
      );
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      notifications = notifications.map((n) => n.copyWith(read: true)).toList();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Бүх мэдэгдлийг уншсан болголоо'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  String _getPriorityText(String priority) {
    switch (priority) {
      case 'high':
        return 'Өндөр';
      case 'medium':
        return 'Дунд';
      case 'low':
        return 'Бага';
      default:
        return priority;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'task':
        return Icons.task;
      case 'announcement':
        return Icons.announcement;
      case 'reminder':
        return Icons.notifications_active;
      case 'warning':
        return Icons.warning;
      case 'congrats':
        return Icons.celebration;
      case 'training':
        return Icons.school;
      default:
        return Icons.notifications;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'task':
        return Colors.blue;
      case 'announcement':
        return Colors.green;
      case 'reminder':
        return Colors.orange;
      case 'warning':
        return Colors.red;
      case 'congrats':
        return Colors.purple;
      case 'training':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(Duration(days: 1));
    final notificationDate = DateTime(date.year, date.month, date.day);

    if (notificationDate == today) {
      return 'Өнөөдөр ${_formatTime(date)}';
    } else if (notificationDate == yesterday) {
      return 'Өчигдөр ${_formatTime(date)}';
    } else {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${_formatTime(date)}';
    }
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _roleLabel(String? role) {
    switch ((role ?? '').toLowerCase()) {
      case 'director':
        return 'Захирал';
      case 'general_manager':
        return 'Ерөнхий менежер';
      case 'supervisor':
        return 'Ахлах';
      case 'worker':
        return 'Ажилтан';
      default:
        return role ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Мэдэгдэл',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _fetchNotifications,
            tooltip: 'Шинэчлэх',
          ),
          if (unreadCount > 0)
            Stack(
              children: [
                IconButton(
                  icon: Icon(Icons.mark_email_read),
                  onPressed: _markAllAsRead,
                  tooltip: 'Бүгдийг уншсан болгох',
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      unreadCount.toString(),
                      style: TextStyle(color: Colors.white, fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                        SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchNotifications,
                          child: Text('Дахин оролдох'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(12.0),
                      child: Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _userName ?? 'Хэрэглэгч',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_userRole != null) ...[
                                SizedBox(height: 4),
                                Text(
                                  _roleLabel(_userRole),
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                              SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildStatCard(
                                    'Нийт',
                                    notifications.length.toString(),
                                    Icons.notifications,
                                  ),
                                  _buildStatCard(
                                    'Уншаагүй',
                                    unreadCount.toString(),
                                    Icons.mark_unread_chat_alt,
                                    isUnread: true,
                                  ),
                                  _buildStatCard(
                                    'Өндөр',
                                    notifications
                                        .where((n) => n.priority == 'high')
                                        .length
                                        .toString(),
                                    Icons.priority_high,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: notifications.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.notifications_none,
                                      size: 56, color: Colors.grey[400]),
                                  SizedBox(height: 12),
                                  Text(
                                    'Мэдэгдэл байхгүй',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _fetchNotifications,
                              child: ListView.builder(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                itemCount: notifications.length,
                                itemBuilder: (context, index) {
                                  return _buildNotificationCard(notifications[index]);
                                },
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon,
      {bool isUnread = false}) {
    return Column(
      children: [
        CircleAvatar(
          backgroundColor:
              isUnread ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
          child: Icon(icon, color: isUnread ? Colors.red : Colors.blue, size: 20),
          radius: 20,
        ),
        SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isUnread ? Colors.red : Colors.black,
          ),
        ),
        Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildNotificationCard(AppNotification notification) {
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: notification.read ? Colors.white : Colors.blue[50],
      child: InkWell(
        onTap: () {
          if (!notification.read) {
            _markAsRead(notification.id);
          }
          _showNotificationDetails(notification);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              _getTypeColor(notification.type).withOpacity(0.1),
                          radius: 16,
                          child: Icon(
                            _getTypeIcon(notification.type),
                            color: _getTypeColor(notification.type),
                            size: 18,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: notification.read ? Colors.black : Colors.blue[900],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!notification.read)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                notification.message,
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getPriorityColor(notification.priority).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _getPriorityColor(notification.priority).withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      _getPriorityText(notification.priority),
                      style: TextStyle(
                        fontSize: 12,
                        color: _getPriorityColor(notification.priority),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    _formatDate(notification.sentAt),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Divider(height: 1),
              SizedBox(height: 8),
              Text(
                'Илгээгч: ${notification.sender}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNotificationDetails(AppNotification notification) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                _getTypeIcon(notification.type),
                color: _getTypeColor(notification.type),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(notification.title, style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(notification.message, style: TextStyle(fontSize: 16)),
                SizedBox(height: 16),
                Divider(),
                SizedBox(height: 8),
                _buildDetailRow('Илгээгч:', notification.sender),
                _buildDetailRow('Төрөл:', _getNotificationTypeText(notification.type)),
                _buildDetailRow('Анхаарал:', _getPriorityText(notification.priority)),
                _buildDetailRow('Илгээсэн:', _formatDate(notification.sentAt)),
                _buildDetailRow('Төлөв:', notification.read ? 'Уншсан' : 'Уншаагүй'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Буцах'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          SizedBox(width: 8),
          Expanded(child: Text(value, style: TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  String _getNotificationTypeText(String type) {
    switch (type) {
      case 'task':
        return 'Даалгавар';
      case 'announcement':
        return 'Ерөнхий мэдэгдэл';
      case 'reminder':
        return 'Сануулга';
      case 'warning':
        return 'Анхааруулга';
      case 'congrats':
        return 'Баяр хүргэлт';
      case 'training':
        return 'Сургалт';
      default:
        return type;
    }
  }
}

/// Fetch unread notification count for badges elsewhere in the app.
Future<int> fetchUnreadNotificationCount() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return 0;

    final response = await http.get(
      Uri.parse('${Url.url}/api/notifications/me/unread-count'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) return 0;
    final jsonResponse = json.decode(response.body);
    return jsonResponse['count'] is int
        ? jsonResponse['count']
        : int.tryParse('${jsonResponse['count']}') ?? 0;
  } catch (_) {
    return 0;
  }
}
