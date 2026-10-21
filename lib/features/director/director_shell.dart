import 'package:flutter/material.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/app_icon.dart';
import '../../shared/widgets/lazy_indexed_stack.dart';
import '../../shared/widgets/notification_bell_action.dart';
import '../profile/profile_screen.dart';
import 'screens/director_attendance_screen.dart';
import 'screens/director_lessons_screen.dart';
import 'screens/director_schedules_screen.dart';
import 'screens/people_screen.dart';

class DirectorShell extends StatefulWidget {
  const DirectorShell({super.key});

  @override
  State<DirectorShell> createState() => _DirectorShellState();
}

class _DirectorShellState extends State<DirectorShell> {
  int _index = 0;

  static const _pages = [
    PeopleScreen(),
    DirectorSchedulesScreen(),
    DirectorLessonsScreen(),
    DirectorAttendanceScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KawanKecil'),
        actions: const [NotificationBellAction(isDirector: true)],
      ),
      // Built on first visit, then kept alive: see LazyIndexedStack for why.
      body: LazyIndexedStack(index: _index, children: _pages),
      bottomNavigationBar: AppBottomNav(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: AppIcon(AppIcons.people),
            selectedIcon: AppIcon(AppIcons.people, filled: true),
            label: 'People',
          ),
          NavigationDestination(
            icon: AppIcon(AppIcons.schedule),
            selectedIcon: AppIcon(AppIcons.schedule, filled: true),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: AppIcon(AppIcons.lessons),
            selectedIcon: AppIcon(AppIcons.lessons, filled: true),
            label: 'Lessons',
          ),
          NavigationDestination(
            icon: AppIcon(AppIcons.attendance),
            selectedIcon: AppIcon(AppIcons.attendance, filled: true),
            label: 'Attendance',
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
