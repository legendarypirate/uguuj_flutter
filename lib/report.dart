import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:taskmanager/color/color.dart';
import 'package:taskmanager/login.dart' as auth;
import 'package:taskmanager/models/task.dart' as task_model;

class ReportScreen extends StatefulWidget {
  @override
  _ReportScreenState createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  DateTimeRange? _selectedDateRange;
  List<auth.User> _subordinates = [];
  List<TaskReport> _taskReports = [];
  bool _isLoading = false;
  bool _isLoadingSubordinates = false;
  bool _isGeneratingPdf = false;
  int? _currentUserId;
  String? _userName;
  String? _userRole;

  /// Embedded TrueType font for PDF (Helvetica cannot render Mongolian Cyrillic).
  pw.Font? _pdfUnicodeFont;
  bool _isLoadingFont = false;

  // Өнгөний тодорхойлолтууд (Opacity-тай)
  final PdfColor blueLight = PdfColor.fromInt(0xFFE3F2FD);
  final PdfColor blueMedium = PdfColor.fromInt(0xFF90CAF9);
  final PdfColor blueDark = PdfColor.fromInt(0xFF1E88E5);
  final PdfColor blueAccent = PdfColor.fromInt(0xFF2962FF);

  final PdfColor greenLight = PdfColor.fromInt(0xFFE8F5E9);
  final PdfColor greenMedium = PdfColor.fromInt(0xFF81C784);
  final PdfColor greenDark = PdfColor.fromInt(0xFF43A047);

  final PdfColor orangeLight = PdfColor.fromInt(0xFFFFF3E0);
  final PdfColor orangeMedium = PdfColor.fromInt(0xFFFFB74D);
  final PdfColor orangeDark = PdfColor.fromInt(0xFFFF9800);

  final PdfColor redLight = PdfColor.fromInt(0xFFFFEBEE);
  final PdfColor redMedium = PdfColor.fromInt(0xFFEF9A9A);
  final PdfColor redDark = PdfColor.fromInt(0xFFE53935);
  final PdfColor redAccent = PdfColor.fromInt(0xFFFF5252);

  final PdfColor purpleLight = PdfColor.fromInt(0xFFF3E5F5);
  final PdfColor purpleMedium = PdfColor.fromInt(0xFFBA68C8);
  final PdfColor purpleDark = PdfColor.fromInt(0xFF8E24AA);

  final PdfColor grey50 = PdfColor.fromInt(0xFFFAFAFA);
  final PdfColor grey100 = PdfColor.fromInt(0xFFF5F5F5);
  final PdfColor grey200 = PdfColor.fromInt(0xFFEEEEEE);
  final PdfColor grey300 = PdfColor.fromInt(0xFFE0E0E0);
  final PdfColor grey400 = PdfColor.fromInt(0xFFBDBDBD);
  final PdfColor grey600 = PdfColor.fromInt(0xFF757575);
  final PdfColor grey700 = PdfColor.fromInt(0xFF616161);
  final PdfColor grey800 = PdfColor.fromInt(0xFF424242);
  final PdfColor grey900 = PdfColor.fromInt(0xFF212121);

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _fetchSubordinates();
    _loadPdfUnicodeFont();
  }

  Future<void> _loadPdfUnicodeFont() async {
    setState(() {
      _isLoadingFont = true;
    });

    try {
      try {
        final fontData =
            await rootBundle.load('assets/fonts/NotoSans-Variable.ttf');
        _pdfUnicodeFont = pw.Font.ttf(fontData);
        print('✅ Noto Sans loaded for PDF (UTF-8 / Cyrillic)');
      } catch (e) {
        print('⚠️ Could not load bundled Noto Sans: $e');
        final font = await _getSystemFont();
        if (font != null) {
          _pdfUnicodeFont = font;
          print('✅ Using system font fallback for PDF');
        } else {
          print('⚠️ No Unicode font — PDF may show tofu for Mongolian text');
        }
      }
    } catch (e) {
      print('❌ Error loading PDF font: $e');
    } finally {
      setState(() {
        _isLoadingFont = false;
      });
    }
  }

  Future<pw.Font?> _getSystemFont() async {
    try {
      final List<String> fontPaths = [
        '/system/fonts/NotoSans-Regular.ttf',
        '/system/fonts/Roboto-Regular.ttf',
        '/System/Library/Fonts/Helvetica.ttc',
        '/System/Library/Fonts/SF-Pro.ttf',
      ];

      for (final path in fontPaths) {
        try {
          final file = File(path);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            return pw.Font.ttf(bytes.buffer.asByteData());
          }
        } catch (e) {
          continue;
        }
      }
    } catch (e) {
      print('Error checking system fonts: $e');
    }
    return null;
  }

  pw.TextStyle _getTextStyle({
    double fontSize = 12,
    pw.FontWeight fontWeight = pw.FontWeight.normal,
    PdfColor color = PdfColors.black,
  }) {
    return pw.TextStyle(
      font: _pdfUnicodeFont,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUserId = prefs.getInt('userId');
      _userName = prefs.getString('userName');
      _userRole = prefs.getString('role');
    });
  }

  Future<void> _fetchSubordinates() async {
    setState(() {
      _isLoadingSubordinates = true;
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
        final usersJson = jsonResponse['data'];

        if (usersJson is List) {
          final allUsers = usersJson.map((userJson) => auth.User.fromJson(userJson)).toList();

          List<auth.User> filteredUsers = [];

          if (_userRole == 'director' || _userRole == 'general_manager') {
            filteredUsers = allUsers.where((user) {
              final role = user.role.toLowerCase();
              return role == 'worker' || role == 'supervisor';
            }).toList();
          } else if (_userRole == 'supervisor') {
            filteredUsers = allUsers.where((user) {
              final isWorker = user.role.toLowerCase() == 'worker';
              final isSubordinate = user.supervisor_id.contains(_currentUserId);
              return isWorker && isSubordinate;
            }).toList();
          } else {
            filteredUsers = [];
          }

          setState(() {
            _subordinates = filteredUsers;
          });

          print('✅ Found ${_subordinates.length} users for user ID: $_currentUserId, Role: $_userRole');
        }
      }
    } catch (e) {
      print('❌ Error fetching subordinates: $e');
      _showErrorSnackBar('Ажилчдын мэдээлэл ачааллахад алдаа гарлаа');
    } finally {
      setState(() {
        _isLoadingSubordinates = false;
      });
    }
  }

  Future<void> _fetchTaskReports() async {
    if (_selectedDateRange == null) {
      _showErrorSnackBar('Хугацааны мужийг сонгоно уу');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        _showErrorSnackBar('Нэвтрэх эрх шаардлагатай');
        return;
      }

      final response = await http.get(
        Uri.parse('${Url.url}/api/task'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        final tasksJson = jsonResponse['data'] ?? [];

        final subordinateIds = _subordinates.map((user) => user.id).toSet();

        List<dynamic> filteredTasks = [];

        // Helper to parse int lists from JSON
        List<int> toIntList(dynamic value) {
          if (value == null) return [];
          if (value is int) return [value];
          if (value is List) {
            return value.map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0).toList();
          }
          return [];
        }

        if (_userRole == 'director' || _userRole == 'general_manager') {
          filteredTasks = tasksJson.where((task) {
            final assignedToList = toIntList(task['assigned_to']);
            final createdAtStr = task['createdAt'];

            if (assignedToList.isEmpty || createdAtStr == null) return false;

            final isSupervisorTask = assignedToList.any((id) =>
                _subordinates.any((user) => user.id == id && user.role.toLowerCase() == 'supervisor'));
            final isWorkerTask = assignedToList.any((id) =>
                _subordinates.any((user) => user.id == id && user.role.toLowerCase() == 'worker'));

            try {
              final createdAt = DateTime.parse(createdAtStr);
              final startDate = _selectedDateRange!.start;
              final endDate = _selectedDateRange!.end.add(Duration(days: 1));

              final isInDateRange = createdAt.isAfter(startDate) && createdAt.isBefore(endDate);

              return (isSupervisorTask || isWorkerTask) && isInDateRange;
            } catch (e) {
              return false;
            }
          }).toList();
        } else if (_userRole == 'supervisor') {
          filteredTasks = tasksJson.where((task) {
            final assignedToList = toIntList(task['assigned_to']);
            final createdAtStr = task['createdAt'];

            if (assignedToList.isEmpty || createdAtStr == null) return false;

            if (!assignedToList.any((id) => subordinateIds.contains(id))) return false;

            try {
              final createdAt = DateTime.parse(createdAtStr);
              final startDate = _selectedDateRange!.start;
              final endDate = _selectedDateRange!.end.add(Duration(days: 1));

              return createdAt.isAfter(startDate) && createdAt.isBefore(endDate);
            } catch (e) {
              return false;
            }
          }).toList();
        } else {
          filteredTasks = [];
        }

        final reportMap = <int, TaskReport>{};

        for (var task in filteredTasks) {
          final assignedToList = toIntList(task['assigned_to']);
          final status = task['status'] as String;
          final priority = task['priority'] as String;
          final title = task['title'] as String;
          final createdAt = task['createdAt'] as String;
          final dueDateStr = task['due_date'] as String?;
          final completedAtStr = task['completed_at']?.toString();
          final updatedAtStr =
              (task['updated_at'] ?? task['updatedAt'])?.toString();

          // Create reports for each assigned user
          for (var assignedTo in assignedToList) {
            if (!subordinateIds.contains(assignedTo)) continue;

            if (!reportMap.containsKey(assignedTo)) {
              final user = _subordinates.firstWhere(
                    (user) => user.id == assignedTo,
                orElse: () => auth.User(
                  id: assignedTo,
                  full_name: 'Тодорхойгүй',
                  phone: '',
                  role: 'unknown',
                  is_active: true,
                ),
              );

              reportMap[assignedTo] = TaskReport(
                worker: user,
                totalTasks: 0,
                pendingTasks: 0,
                inProgressTasks: 0,
                doneTasks: 0,
                verifiedTasks: 0,
                cancelledTasks: 0,
                highPriorityTasks: 0,
                normalPriorityTasks: 0,
                lowPriorityTasks: 0,
                onTimeCompletedTasks: 0,
                lateCompletedTasks: 0,
                overduePendingTasks: 0,
                tasks: [],
                completedTasks: [],
                onTimeCompletedTasksList: [],
                lateCompletedTasksList: [],
                pendingTasksList: [],
                overduePendingTasksList: [],
                cancelledTasksList: [],
              );
            }

          final report = reportMap[assignedTo]!;
          report.totalTasks++;

          DateTime? updatedAtParsed;
          if (updatedAtStr != null) {
            try {
              updatedAtParsed = DateTime.parse(updatedAtStr);
            } catch (_) {}
          }

          final isOverdue = task_model.Task.checkIsOverdue(status, dueDateStr);
          final isLateCompleted = task_model.Task.checkWasCompletedLate(
            status,
            dueDateStr,
            completedAtStr,
            updatedAtParsed,
          );

          final taskInfo = TaskInfo(
            title: title,
            status: status,
            priority: priority,
            createdAt: createdAt,
            dueDate: dueDateStr,
            completedAt: completedAtStr,
            isOverdue: isOverdue,
            isLateCompleted: isLateCompleted,
          );

          report.tasks.add(taskInfo);

          if (status == 'done' || status == 'verified') {
            report.completedTasks.add(taskInfo);
            if (isLateCompleted) {
              report.lateCompletedTasks++;
              report.lateCompletedTasksList.add(taskInfo);
            } else if (dueDateStr != null) {
              report.onTimeCompletedTasks++;
              report.onTimeCompletedTasksList.add(taskInfo);
            } else {
              report.onTimeCompletedTasks++;
              report.onTimeCompletedTasksList.add(taskInfo);
            }
          } else if (status == 'pending' || status == 'in_progress') {
            report.pendingTasksList.add(taskInfo);
            if (isOverdue) {
              report.overduePendingTasks++;
              report.overduePendingTasksList.add(taskInfo);
            }
          } else if (status == 'cancelled') {
            report.cancelledTasksList.add(taskInfo);
          }

          switch (status) {
            case 'pending':
              report.pendingTasks++;
              break;
            case 'in_progress':
              report.inProgressTasks++;
              break;
            case 'done':
              report.doneTasks++;
              break;
            case 'verified':
              report.verifiedTasks++;
              break;
            case 'cancelled':
              report.cancelledTasks++;
              break;
          }

          switch (priority) {
            case 'high':
              report.highPriorityTasks++;
              break;
            case 'normal':
              report.normalPriorityTasks++;
              break;
            case 'low':
              report.lowPriorityTasks++;
              break;
          }
          } // end for assignedTo in assignedToList
        } // end for task in filteredTasks

        final sortedReports = reportMap.values.toList()
          ..sort((a, b) {
            final aIsSupervisor = a.worker.role.toLowerCase() == 'supervisor';
            final bIsSupervisor = b.worker.role.toLowerCase() == 'supervisor';

            if (aIsSupervisor && !bIsSupervisor) return -1;
            if (!aIsSupervisor && bIsSupervisor) return 1;

            return a.worker.full_name.compareTo(b.worker.full_name);
          });

        setState(() {
          _taskReports = sortedReports;
          _isLoading = false;
        });

        print('✅ Generated ${_taskReports.length} task reports');
      }
    } catch (e) {
      print('❌ Error fetching task reports: $e');
      _showErrorSnackBar('Тайлан ачааллахад алдаа гарлаа');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Хугацааны мужийг сонгох',
      cancelText: 'Цуцлах',
      confirmText: 'Сонгох',
      saveText: 'Хадгалах',
      fieldStartLabelText: 'Эхлэх огноо',
      fieldEndLabelText: 'Дуусах огноо',
      initialDateRange: _selectedDateRange,
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
      });
      _fetchTaskReports();
    }
  }

  Future<void> _generateAndSharePDF() async {
    if (_taskReports.isEmpty) {
      _showErrorSnackBar('Тайлангийн мэдээлэл байхгүй байна');
      return;
    }

    if (_isLoadingFont) {
      _showErrorSnackBar('Фонт ачааллаж байна. Түр хүлээнэ үү');
      return;
    }

    if (_pdfUnicodeFont == null) {
      _showErrorSnackBar(
        'PDF фонт ачааллаагүй. assets/fonts/NotoSans-Variable.ttf шалгана уу',
      );
      return;
    }

    setState(() {
      _isGeneratingPdf = true;
    });

    try {
      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(
          base: _pdfUnicodeFont!,
          bold: _pdfUnicodeFont!,
        ),
      );

      // 1. Cover page
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(20),
          build: (pw.Context context) {
            return _buildCoverPage();
          },
        ),
      );

      // 2. Summary page
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(20),
          build: (pw.Context context) {
            return _buildSummaryPage();
          },
        ),
      );

      // 3. Individual worker reports (one per page)
      for (int i = 0; i < _taskReports.length; i++) {
        final report = _taskReports[i];

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.all(20),
            build: (pw.Context context) {
              return _buildWorkerReportPage(report, i);
            },
          ),
        );
      }

      final dir = await getTemporaryDirectory();
      final fileName = 'task_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      setState(() {
        _isGeneratingPdf = false;
      });

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Даалгаврын тайлан',
        text: 'Даалгаврын тайлан - ${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start)} - ${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end)}\nХянагч: $_userName ($_userRole)',
      );

      _showSuccessSnackBar('PDF тайлан амжилттай үүсгэгдлээ');

    } catch (e) {
      print('❌ Error generating PDF: $e');
      setState(() {
        _isGeneratingPdf = false;
      });
      _showErrorSnackBar('PDF үүсгэхэд алдаа гарлаа: ${e.toString()}');
    }
  }

  // PDF Page Builders
  pw.Widget _buildCoverPage() {
    return pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 120,
          height: 120,
          decoration: pw.BoxDecoration(
            color: blueLight,
            shape: pw.BoxShape.circle,
            border: pw.Border.all(color: blueDark, width: 3),
          ),
          child: pw.Center(
            child: pw.Text(
              '📊',
              style: _getTextStyle(fontSize: 50),
            ),
          ),
        ),

        pw.SizedBox(height: 40),

        pw.Text(
          'Даалгаврын Тайлан',
          style: _getTextStyle(
            fontSize: 36,
            fontWeight: pw.FontWeight.bold,
            color: blueDark,
          ),
          textAlign: pw.TextAlign.center,
        ),

        pw.SizedBox(height: 20),

        pw.Container(
          height: 3,
          width: 200,
          color: blueMedium,
        ),

        pw.SizedBox(height: 40),

        pw.Container(
          padding: pw.EdgeInsets.all(25),
          decoration: pw.BoxDecoration(
            color: grey50,
            borderRadius: pw.BorderRadius.circular(15),
            border: pw.Border.all(color: grey300, width: 1.5),
          ),
          child: pw.Column(
            children: [
              _buildInfoRowPdf('Хугацаа:', '${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start)} - ${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end)}'),
              pw.SizedBox(height: 12),
              _buildInfoRowPdf('Хянагч:', '$_userName ($_userRole)'),
              pw.SizedBox(height: 12),
              _buildInfoRowPdf('Үүсгэсэн огноо:', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())),
              pw.SizedBox(height: 12),
              _buildInfoRowPdf('Нийт ажилтан:', _subordinates.length.toString()),
              pw.SizedBox(height: 12),
              _buildInfoRowPdf('Нийт даалгавар:', _taskReports.fold(0, (sum, report) => sum + report.totalTasks).toString()),
            ],
          ),
        ),

        pw.SizedBox(height: 50),

        pw.Text(
          'Тайлан гаргасан: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
          style: _getTextStyle(
            fontSize: 14,
            color: grey600,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildSummaryPage() {
    final totalTasks = _taskReports.fold(0, (sum, report) => sum + report.totalTasks);
    final totalPending = _taskReports.fold(0, (sum, report) => sum + report.pendingTasks);
    final totalDone = _taskReports.fold(0, (sum, report) => sum + report.doneTasks + report.verifiedTasks);
    final totalOnTime = _taskReports.fold(0, (sum, report) => sum + report.onTimeCompletedTasks);
    final totalLate = _taskReports.fold(0, (sum, report) => sum + report.lateCompletedTasks);
    final totalOverduePending = _taskReports.fold(0, (sum, report) => sum + report.overduePendingTasks);
    final totalCancelled = _taskReports.fold(0, (sum, report) => sum + report.cancelledTasks);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Ерөнхий тайлан',
          style: _getTextStyle(
            fontSize: 28,
            fontWeight: pw.FontWeight.bold,
            color: blueDark,
          ),
        ),

        pw.SizedBox(height: 20),

        // Overall statistics
        pw.GridView(
          crossAxisCount: 3,
          childAspectRatio: 1.5,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: [
            _buildStatCardPdf('Нийт\nажилтан', _subordinates.length.toString(), blueDark),
            _buildStatCardPdf('Нийт\nдаалгавар', totalTasks.toString(), greenDark),
            _buildStatCardPdf('Хүлээгдэж\nбайгаа', totalPending.toString(), orangeDark),
            _buildStatCardPdf('Дууссан', totalDone.toString(), greenDark),
            _buildStatCardPdf('Цагтаа\nдууссан', totalOnTime.toString(), greenDark),
            _buildStatCardPdf('Хоцорч\nдууссан', totalLate.toString(), redDark),
            _buildStatCardPdf('Хугацаа\nхэтэрсэн', totalOverduePending.toString(), redAccent),
            _buildStatCardPdf('Цуцлагдсан', totalCancelled.toString(), redDark),
          ],
        ),

        pw.SizedBox(height: 30),

        pw.Text(
          'Ажилчдын хураангуй',
          style: _getTextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: grey800,
          ),
        ),

        pw.SizedBox(height: 10),

        // Worker summary table
        pw.Table.fromTextArray(
          border: null,
          headerStyle: _getTextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: pw.BoxDecoration(color: blueDark),
          headers: ['№', 'Ажилтан', 'Дугаар', 'Даалгавар', 'Хүлээгдэж', 'Цагтаа', 'Хоцорсон', 'Хэтэрсэн'],
          data: _taskReports.asMap().entries.map((entry) {
            final index = entry.key;
            final report = entry.value;
            return [
              '${index + 1}',
              report.worker.full_name,
              report.worker.phone,
              report.totalTasks.toString(),
              report.pendingTasks.toString(),
              report.onTimeCompletedTasks.toString(),
              report.lateCompletedTasks.toString(),
              report.overduePendingTasks.toString(),
            ];
          }).toList(),
          cellAlignment: pw.Alignment.centerLeft,
          cellStyle: _getTextStyle(fontSize: 11),
          rowDecoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: grey300, width: 0.5),
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildWorkerReportPage(TaskReport report, int workerIndex) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '${workerIndex + 1}. Ажилтны тайлан',
          style: _getTextStyle(
            fontSize: 24,
            fontWeight: pw.FontWeight.bold,
            color: blueDark,
          ),
        ),

        pw.SizedBox(height: 20),

        // Worker info card
        pw.Container(
          decoration: pw.BoxDecoration(
            color: blueLight,
            borderRadius: pw.BorderRadius.circular(10),
            border: pw.Border.all(color: blueMedium, width: 1.5),
          ),
          padding: pw.EdgeInsets.all(16),
          child: pw.Row(
            children: [
              pw.Container(
                width: 50,
                height: 50,
                decoration: pw.BoxDecoration(
                  color: blueMedium,
                  shape: pw.BoxShape.circle,
                  border: pw.Border.all(color: blueDark, width: 2),
                ),
                child: pw.Center(
                  child: pw.Text(
                    report.worker.full_name.isNotEmpty
                        ? report.worker.full_name[0].toUpperCase()
                        : '?',
                    style: _getTextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ),
              ),

              pw.SizedBox(width: 16),

              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      report.worker.full_name,
                      style: _getTextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: blueDark,
                      ),
                    ),

                    pw.Row(
                      children: [
                        pw.Text(
                          'Утас: ${report.worker.phone} • ',
                          style: _getTextStyle(
                            fontSize: 12,
                            color: grey600,
                          ),
                        ),

                        pw.Container(
                          padding: pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: pw.BoxDecoration(
                            color: report.worker.role.toLowerCase() == 'supervisor'
                                ? purpleLight
                                : greenLight,
                            borderRadius: pw.BorderRadius.circular(12),
                            border: pw.Border.all(
                              color: report.worker.role.toLowerCase() == 'supervisor'
                                  ? purpleMedium
                                  : greenMedium,
                            ),
                          ),
                          child: pw.Text(
                            report.worker.role.toLowerCase() == 'supervisor' ? 'Ахлах' : 'Ажилтан',
                            style: _getTextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: report.worker.role.toLowerCase() == 'supervisor'
                                  ? purpleDark
                                  : greenDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              pw.Container(
                padding: pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: pw.BoxDecoration(
                  color: blueMedium,
                  borderRadius: pw.BorderRadius.circular(20),
                  border: pw.Border.all(color: blueDark, width: 1.5),
                ),
                child: pw.Text(
                  'Нийт: ${report.totalTasks}',
                  style: _getTextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ),
            ],
          ),
        ),

        pw.SizedBox(height: 25),

        // Statistics grid
        pw.Text(
          'Статистик',
          style: _getTextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            color: grey800,
          ),
        ),

        pw.SizedBox(height: 10),

        pw.GridView(
          crossAxisCount: 3,
          childAspectRatio: 1.3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          children: [
            _buildMiniStatCardPdf('Хүлээгдэж', report.pendingTasks.toString(), orangeDark),
            _buildMiniStatCardPdf('Хийгдэж\nбайгаа', report.inProgressTasks.toString(), blueDark),
            _buildMiniStatCardPdf('Дууссан', report.doneTasks.toString(), greenDark),
            _buildMiniStatCardPdf('Цагтаа\nдууссан', report.onTimeCompletedTasks.toString(), greenDark),
            _buildMiniStatCardPdf('Хоцорч\nдууссан', report.lateCompletedTasks.toString(), redDark),
            _buildMiniStatCardPdf('Хугацаа\nхэтэрсэн', report.overduePendingTasks.toString(), redAccent),
            _buildMiniStatCardPdf('Баталгаа\nжсан', report.verifiedTasks.toString(), purpleDark),
            _buildMiniStatCardPdf('Цуцлагд\nсан', report.cancelledTasks.toString(), redDark),
          ],
        ),

        pw.SizedBox(height: 25),

        // Completed on time
        _buildTaskSectionPdf(
          title: 'Цагтаа дууссан (${report.onTimeCompletedTasksList.length})',
          tasks: report.onTimeCompletedTasksList,
          color: greenDark,
          emptyText: 'Цагтаа дууссан ажил байхгүй',
        ),

        pw.SizedBox(height: 20),

        // Completed late
        _buildTaskSectionPdf(
          title: 'Хугацаа хэтэрч дууссан (${report.lateCompletedTasksList.length})',
          tasks: report.lateCompletedTasksList,
          color: redDark,
          emptyText: 'Хоцорч дууссан ажил байхгүй',
        ),

        pw.SizedBox(height: 20),

        // Pending tasks
        _buildTaskSectionPdf(
          title: 'Дуусаагүй ажлууд (${report.pendingTasksList.length})',
          tasks: report.pendingTasksList,
          color: orangeDark,
          emptyText: 'Дуусаагүй ажил байхгүй',
          showStatus: true,
        ),

        pw.SizedBox(height: 20),

        // Overdue pending
        _buildTaskSectionPdf(
          title: 'Хугацаа хэтэрсэн (${report.overduePendingTasksList.length})',
          tasks: report.overduePendingTasksList,
          color: redAccent,
          emptyText: 'Хугацаа хэтэрсэн ажил байхгүй',
          showStatus: true,
        ),

        pw.SizedBox(height: 20),

        // Cancelled tasks
        _buildTaskSectionPdf(
          title: 'Цуцлагдсан ажлууд (${report.cancelledTasksList.length})',
          tasks: report.cancelledTasksList,
          color: redDark,
          emptyText: 'Цуцлагдсан ажил байхгүй',
        ),
      ],
    );
  }

  // PDF Helper Methods
  pw.Widget _buildInfoRowPdf(String label, String value) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: _getTextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: grey700,
          ),
        ),

        pw.SizedBox(width: 10),

        pw.Expanded(
          child: pw.Text(
            value,
            style: _getTextStyle(
              fontSize: 14,
              color: grey800,
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildStatCardPdf(String title, String value, PdfColor color) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: color, width: 1.5),
        // boxShadow: [
        //   pw.BoxShadow(
        //     color: grey300,
        //     blurRadius: 4,
        //     offset: pw.Offset(2, 2),
        //   ),
        // ],
      ),
      padding: pw.EdgeInsets.all(12),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            value,
            style: _getTextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
            textAlign: pw.TextAlign.center,
          ),

          pw.SizedBox(height: 6),

          pw.Text(
            title,
            style: _getTextStyle(
              fontSize: 10,
              color: grey700,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }

  pw.Widget _buildMiniStatCardPdf(String title, String value, PdfColor color) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: grey50,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: color, width: 1),
      ),
      padding: pw.EdgeInsets.all(8),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            value,
            style: _getTextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),

          pw.SizedBox(height: 4),

          pw.Text(
            title,
            style: _getTextStyle(
              fontSize: 8,
              color: grey700,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTaskSectionPdf({
    required String title,
    required List<TaskInfo> tasks,
    required PdfColor color,
    required String emptyText,
    bool showStatus = false,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: _getTextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),

        pw.SizedBox(height: 10),

        if (tasks.isEmpty)
          pw.Container(
            width: double.infinity,
            padding: pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: grey100,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: grey300),
            ),
            child: pw.Text(
              emptyText,
              style: _getTextStyle(
                fontSize: 12,
                color: grey600,
              ),
              textAlign: pw.TextAlign.center,
            ),
          )
        else
          pw.Column(
            children: tasks.take(15).map((task) { // Limit to 15 tasks per section
              final dueDate = task.dueDate != null
                  ? DateFormat('yyyy-MM-dd').format(DateTime.parse(task.dueDate!))
                  : null;

              return pw.Container(
                margin: pw.EdgeInsets.only(bottom: 6),
                padding: pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: grey50,
                  borderRadius: pw.BorderRadius.circular(4),
                  border: pw.Border.all(color: grey200),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 6,
                      height: 6,
                      margin: pw.EdgeInsets.only(top: 6, right: 8),
                      decoration: pw.BoxDecoration(
                        color: color,
                        shape: pw.BoxShape.circle,
                      ),
                    ),

                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            task.title,
                            style: _getTextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),

                          if (showStatus)
                            pw.Container(
                              margin: pw.EdgeInsets.only(top: 2),
                              child: pw.Text(
                                'Төлөв: ${_getStatusText(task.status)}',
                                style: _getTextStyle(
                                  fontSize: 10,
                                  color: grey600,
                                ),
                              ),
                            ),

                          if (dueDate != null)
                            pw.Container(
                              margin: pw.EdgeInsets.only(top: 2),
                              child: pw.Text(
                                'Дуусах: $dueDate',
                                style: _getTextStyle(
                                  fontSize: 10,
                                  color: grey600,
                                ),
                              ),
                            ),

                          if (task.timelinessText != null)
                            pw.Container(
                              margin: pw.EdgeInsets.only(top: 2),
                              child: pw.Text(
                                task.timelinessText!,
                                style: _getTextStyle(
                                  fontSize: 10,
                                  color: task.isLateCompleted || task.isOverdue
                                      ? redDark
                                      : greenDark,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),

        if (tasks.length > 15)
          pw.Container(
            margin: pw.EdgeInsets.only(top: 8),
            padding: pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: grey100,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              '+ ${tasks.length - 15} даалгавар харуулаагүй',
              style: _getTextStyle(
                fontSize: 10,
                color: grey600,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
      ],
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
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
            Icon(Icons.check_circle, color: Colors.white),
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Тайлан'),
        centerTitle: true,
        actions: [
          if (_taskReports.isNotEmpty)
            IconButton(
              icon: Icon(Icons.picture_as_pdf),
              onPressed: (_isGeneratingPdf || _pdfUnicodeFont == null)
                  ? null
                  : _generateAndSharePDF,
              tooltip: 'PDF тайлан үүсгэх',
            ),
        ],
      ),
      body: _isLoadingFont
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Date range selection
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.blue.shade100, width: 1),
              ),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Хугацааны муж',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _selectDateRange(context),
                      icon: Icon(Icons.calendar_today, color: Colors.blue),
                      label: Text(
                        _selectedDateRange != null
                            ? '${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start)} - ${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end)}'
                            : 'Огноо сонгох',
                        style: TextStyle(color: Colors.blue.shade800),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size(double.infinity, 50),
                        side: BorderSide(color: Colors.blue.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        backgroundColor: Colors.blue.shade50,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 16),

            // Workers information
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.green.shade100, width: 1),
              ),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Өөрийн удирдлагад ажилчид',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade800,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.refresh, color: Colors.green),
                          onPressed: _fetchSubordinates,
                          tooltip: 'Шинэчлэх',
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    _isLoadingSubordinates
                        ? Center(child: CircularProgressIndicator())
                        : _subordinates.isEmpty
                        ? Center(
                      child: Column(
                        children: [
                          Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
                          SizedBox(height: 12),
                          Text(
                            'Ажилчид олдсонгүй',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                        : Column(
                      children: _subordinates.map((worker) {
                        return Card(
                          margin: EdgeInsets.only(bottom: 8),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade100,
                              child: Text(
                                worker.full_name.isNotEmpty
                                    ? worker.full_name[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: Colors.blue.shade800,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              worker.full_name,
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text('Утас: ${worker.phone}'),
                            trailing: Container(
                              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: worker.role.toLowerCase() == 'supervisor'
                                      ? [Colors.purple.shade50, Colors.purple.shade100]
                                      : [Colors.green.shade50, Colors.green.shade100],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: worker.role.toLowerCase() == 'supervisor'
                                      ? Colors.purple.shade200
                                      : Colors.green.shade200,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                worker.role.toLowerCase() == 'supervisor' ? 'Ахлах' : 'Ажилтан',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: worker.role.toLowerCase() == 'supervisor'
                                      ? Colors.purple.shade800
                                      : Colors.green.shade800,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 16),

            if (_selectedDateRange != null)
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.blueGrey.shade100, width: 1),
                ),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Даалгаврын тайлан',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.blueGrey.shade800,
                            ),
                          ),
                          if (_taskReports.isNotEmpty)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.blue.shade500, Colors.blue.shade600],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Нийт: ${_taskReports.fold(0, (sum, report) => sum + report.totalTasks)}',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: 12),

                      _isLoading
                          ? Center(child: CircularProgressIndicator())
                          : _taskReports.isEmpty
                          ? Center(
                        child: Column(
                          children: [
                            Icon(Icons.assignment_outlined, size: 48, color: Colors.grey[400]),
                            SizedBox(height: 12),
                            Text(
                              'Тухайн хугацаанд даалгавар олдсонгүй',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                          : Column(
                        children: _taskReports.map((report) {
                          return Card(
                            elevation: 2,
                            margin: EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade200, width: 1),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Worker info header
                                  Container(
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Colors.blue.shade50, Colors.lightBlue.shade50],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.blue.shade200, width: 1.5),
                                    ),
                                    child: Row(
                                      children: [

                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                report.worker.full_name,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 16,
                                                  color: Colors.blue.shade900,
                                                ),
                                              ),
                                              SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      '${report.worker.phone} • ',
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: Colors.grey[600],
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(width: 4),
                                                  Container(
                                                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        colors: report.worker.role.toLowerCase() == 'supervisor'
                                                            ? [Colors.purple.shade50, Colors.purple.shade100]
                                                            : [Colors.green.shade50, Colors.green.shade100],
                                                      ),
                                                      borderRadius: BorderRadius.circular(12),
                                                      border: Border.all(
                                                        color: report.worker.role.toLowerCase() == 'supervisor'
                                                            ? Colors.purple.shade200
                                                            : Colors.green.shade200,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      report.worker.role.toLowerCase() == 'supervisor'
                                                          ? 'Ахлах'
                                                          : 'Ажилтан',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w600,
                                                        color: report.worker.role.toLowerCase() == 'supervisor'
                                                            ? Colors.purple.shade800
                                                            : Colors.green.shade800,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              )

                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade100,
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: Colors.blue.shade300, width: 1.5),
                                          ),
                                          child: Text(
                                            'Нийт: ${report.totalTasks}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue.shade800,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  SizedBox(height: 16),

                                  // On-time completed
                                  _buildTaskListSection(
                                    title: 'Цагтаа дууссан - ${report.onTimeCompletedTasksList.length}',
                                    tasks: report.onTimeCompletedTasksList,
                                    color: Colors.green,
                                    emptyText: 'Цагтаа дууссан ажил байхгүй',
                                    icon: Icons.check_circle,
                                  ),

                                  SizedBox(height: 12),

                                  // Late completed
                                  _buildTaskListSection(
                                    title: 'Хугацаа хэтэрч дууссан - ${report.lateCompletedTasksList.length}',
                                    tasks: report.lateCompletedTasksList,
                                    color: Colors.red,
                                    emptyText: 'Хоцорч дууссан ажил байхгүй',
                                    icon: Icons.warning_amber_rounded,
                                  ),

                                  SizedBox(height: 12),

                                  // Pending/In Progress Tasks Section
                                  _buildTaskListSection(
                                    title: 'Дуусаагүй ажлууд - ${report.pendingTasksList.length}',
                                    tasks: report.pendingTasksList,
                                    color: Colors.orange,
                                    emptyText: 'Дуусаагүй ажил байхгүй',
                                    icon: Icons.pending,
                                    showStatus: true,
                                  ),

                                  SizedBox(height: 12),

                                  // Overdue pending
                                  _buildTaskListSection(
                                    title: 'Хугацаа хэтэрсэн - ${report.overduePendingTasksList.length}',
                                    tasks: report.overduePendingTasksList,
                                    color: Colors.red[700]!,
                                    emptyText: 'Хугацаа хэтэрсэн ажил байхгүй',
                                    icon: Icons.schedule,
                                    showStatus: true,
                                  ),

                                  SizedBox(height: 12),

                                  // Cancelled Tasks Section
                                  _buildTaskListSection(
                                    title: 'Цуцлагдсан ажлууд - ${report.cancelledTasksList.length}',
                                    tasks: report.cancelledTasksList,
                                    color: Colors.red,
                                    emptyText: 'Цуцлагдсан ажил байхгүй',
                                    icon: Icons.cancel,
                                  ),

                                  SizedBox(height: 16),

                                  // Statistics grid
                                  GridView.count(
                                    crossAxisCount: 3,
                                    shrinkWrap: true,
                                    physics: NeverScrollableScrollPhysics(),
                                    childAspectRatio: 1.5,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                    children: [
                                      _buildStatCard('Хүлээгдэж', report.pendingTasks, Colors.orange),
                                      _buildStatCard('Хийгдэж', report.inProgressTasks, Colors.blue),
                                      _buildStatCard('Цагтаа', report.onTimeCompletedTasks, Colors.green),
                                      _buildStatCard('Хоцорсон', report.lateCompletedTasks, Colors.red),
                                      _buildStatCard('Хэтэрсэн', report.overduePendingTasks, Colors.red[700]!),
                                      _buildStatCard('Цуцлагд', report.cancelledTasks, Colors.red),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),

            if (_taskReports.isNotEmpty && !_isGeneratingPdf)
              Padding(
                padding: EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed:
                      _pdfUnicodeFont == null ? null : _generateAndSharePDF,
                  icon: _isGeneratingPdf
                      ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                      : Icon(Icons.picture_as_pdf),
                  label: Text(_isGeneratingPdf ? 'PDF үүсгэж байна...' : 'PDF тайлан үүсгэх'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size(double.infinity, 50),
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskListSection({
    required String title,
    required List<TaskInfo> tasks,
    required Color color,
    required String emptyText,
    required IconData icon,
    bool showStatus = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: color,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        if (tasks.isEmpty)
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Text(
              emptyText,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Column(
              children: tasks.map((task) {
                final statusText = showStatus ? _getStatusText(task.status) : '';
                final dueDate = task.dueDate != null
                    ? DateFormat('yyyy-MM-dd').format(DateTime.parse(task.dueDate!))
                    : null;

                return Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: tasks.last != task
                          ? BorderSide(color: color.withOpacity(0.1))
                          : BorderSide.none,
                    ),
                  ),
                  padding: EdgeInsets.all(10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: EdgeInsets.only(top: 6, right: 10),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (showStatus && statusText.isNotEmpty)
                              Container(
                                margin: EdgeInsets.only(top: 4),
                                child: Text(
                                  'Төлөв: $statusText',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                            if (dueDate != null)
                              Container(
                                margin: EdgeInsets.only(top: 2),
                                child: Row(
                                  children: [
                                    Icon(Icons.schedule, size: 12, color: Colors.grey[500]),
                                    SizedBox(width: 4),
                                    Text(
                                      'Дуусах: $dueDate',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: task.isOverdue
                                            ? Colors.red[700]
                                            : Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (task.timelinessText != null)
                              Container(
                                margin: EdgeInsets.only(top: 4),
                                child: Text(
                                  task.timelinessText!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: task.isLateCompleted || task.isOverdue
                                        ? Colors.red[700]
                                        : Colors.green[700],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildStatCard(String title, int count, Color color) {
    return Container(
      margin: EdgeInsets.all(4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              color: color.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Хүлээгдэж байгаа';
      case 'in_progress':
        return 'Хийгдэж байгаа';
      case 'done':
        return 'Дууссан';
      case 'verified':
        return 'Баталгаажсан';
      case 'cancelled':
        return 'Цуцлагдсан';
      default:
        return status;
    }
  }
}

class TaskReport {
  final auth.User worker;
  int totalTasks;
  int pendingTasks;
  int inProgressTasks;
  int doneTasks;
  int verifiedTasks;
  int cancelledTasks;
  int highPriorityTasks;
  int normalPriorityTasks;
  int lowPriorityTasks;
  int onTimeCompletedTasks;
  int lateCompletedTasks;
  int overduePendingTasks;
  List<TaskInfo> tasks;
  List<TaskInfo> completedTasks;
  List<TaskInfo> onTimeCompletedTasksList;
  List<TaskInfo> lateCompletedTasksList;
  List<TaskInfo> pendingTasksList;
  List<TaskInfo> overduePendingTasksList;
  List<TaskInfo> cancelledTasksList;

  TaskReport({
    required this.worker,
    required this.totalTasks,
    required this.pendingTasks,
    required this.inProgressTasks,
    required this.doneTasks,
    required this.verifiedTasks,
    required this.cancelledTasks,
    required this.highPriorityTasks,
    required this.normalPriorityTasks,
    required this.lowPriorityTasks,
    required this.onTimeCompletedTasks,
    required this.lateCompletedTasks,
    required this.overduePendingTasks,
    required this.tasks,
    required this.completedTasks,
    required this.onTimeCompletedTasksList,
    required this.lateCompletedTasksList,
    required this.pendingTasksList,
    required this.overduePendingTasksList,
    required this.cancelledTasksList,
  });
}

class TaskInfo {
  final String title;
  final String status;
  final String priority;
  final String createdAt;
  final String? dueDate;
  final String? completedAt;
  final bool isOverdue;
  final bool isLateCompleted;

  TaskInfo({
    required this.title,
    required this.status,
    required this.priority,
    required this.createdAt,
    this.dueDate,
    this.completedAt,
    this.isOverdue = false,
    this.isLateCompleted = false,
  });

  String? get timelinessText {
    if (isOverdue) return 'Хугацаа хэтэрсэн';
    if (isLateCompleted) return 'Хугацаа хэтэрч дууссан';
    if (status == 'done' || status == 'verified') {
      if (dueDate != null) return 'Цагтаа дууссан';
    }
    return null;
  }
}