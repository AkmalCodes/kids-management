import 'package:flutter/material.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/notification_bell_action.dart';
import '../profile/profile_screen.dart';
import 'screens/mark_attendance_screen.dart';
import 'screens/teacher_lesson_plans_screen.dart';
import 'screens/teacher_reports_screen.dart';
import 'screens/teacher_schedule_screen.dart';

class TeacherShell extends StatefulWidget {
  const TeacherShell({super.key});

  @override
  State<TeacherShell> createState() => _TeacherShellState();
}

class _TeacherShellState extends State<TeacherShell> {
  int _index = 0;

  static const _pages = [
    TeacherScheduleScreen(),
    MarkAttendanceScreen(),
    TeacherLessonPlansScreen(),
    TeacherReportsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Childcare Manager'),
        actions: const [NotificationBellAction(isDirector: false)],
      ),
      body: _pages[_index],
      bottomNavigationBar: AppBottomNav(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.check_circle_outline),
            selectedIcon: Icon(Icons.check_circle),
            label: 'Attendance',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Lessons',
          ),
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            selectedIcon: Icon(Icons.article),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
