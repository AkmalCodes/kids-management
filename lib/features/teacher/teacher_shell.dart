import 'package:flutter/material.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/app_icon.dart';
import '../../shared/widgets/lazy_indexed_stack.dart';
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
        title: const Text('KawanKecil'),
        actions: const [NotificationBellAction(isDirector: false)],
      ),
      // Built on first visit, then kept alive: see LazyIndexedStack for why.
      body: LazyIndexedStack(index: _index, children: _pages),
      bottomNavigationBar: AppBottomNav(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: AppIcon(AppIcons.schedule),
            selectedIcon: AppIcon(AppIcons.schedule, filled: true),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: AppIcon(AppIcons.attendance),
            selectedIcon: AppIcon(AppIcons.attendance, filled: true),
            label: 'Attendance',
          ),
          NavigationDestination(
            icon: AppIcon(AppIcons.lessons),
            selectedIcon: AppIcon(AppIcons.lessons, filled: true),
            label: 'Lessons',
          ),
          NavigationDestination(
            icon: AppIcon(AppIcons.reports),
            selectedIcon: AppIcon(AppIcons.reports, filled: true),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: AppIcon(AppIcons.profile),
            selectedIcon: AppIcon(AppIcons.profile, filled: true),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
