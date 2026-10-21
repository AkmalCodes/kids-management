import 'package:flutter/material.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/app_icon.dart';
import '../../shared/widgets/lazy_indexed_stack.dart';
import '../profile/profile_screen.dart';
import 'screens/child_attendance_screen.dart';
import 'screens/child_reports_screen.dart';
import 'screens/child_schedule_screen.dart';

// StatefulWidget (not Riverpod) for the tab index: this is purely local UI
// state — which tab is selected — that no other widget needs to know
// about, so plain setState is simpler than wiring up a provider for it.
class ParentShell extends StatefulWidget {
  const ParentShell({super.key});

  @override
  State<ParentShell> createState() => _ParentShellState();
}

class _ParentShellState extends State<ParentShell> {
  int _index = 0;

  // Index in this list must line up with the order of BottomNavigationBarItems
  // below — index 0 is Schedule, 1 is Attendance, 2 is Reports.
  static const _pages = [
    ChildScheduleScreen(),
    ChildAttendanceScreen(),
    ChildReportsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KawanKecil'),
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
