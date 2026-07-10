import 'package:flutter/material.dart';

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
    Center(child: Text('Schedule — coming soon')),
    Center(child: Text('Attendance — coming soon')),
    Center(child: Text('Reports — coming soon')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Childcare Manager'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Schedule',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.check_circle_outline),
            label: 'Attendance',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.article_outlined),
            label: 'Reports',
          ),
        ],
      ),
    );
  }
}
