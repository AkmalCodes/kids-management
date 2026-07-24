import 'package:flutter/material.dart';
import '../profile/profile_screen.dart';
import 'screens/director_attendance_screen.dart';
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
    Center(child: Text('Lesson Plans — coming soon')),
    DirectorAttendanceScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Childcare Manager'),
      ),
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'People',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Lessons',
          ),
          NavigationDestination(
            icon: Icon(Icons.check_circle_outline),
            selectedIcon: Icon(Icons.check_circle),
            label: 'Attendance',
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
