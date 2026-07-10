import 'package:flutter/material.dart';

// Placeholder for now — Task 7 adds the real BottomNavigationBar + tabs.
// Exists as its own widget/file (rather than inline in RoleRouter) so each
// role's screen can grow independently without bloating the router.
class ParentShell extends StatelessWidget {
  const ParentShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Parent')));
  }
}
