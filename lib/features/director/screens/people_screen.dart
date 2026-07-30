import 'package:flutter/material.dart';
import 'manage_children_screen.dart';
import 'manage_classes_screen.dart';
import 'manage_teachers_screen.dart';

// Hosts both account/enrollment management screens under one nav
// destination -- Teachers and Children are two facets of the same job
// (director provisions accounts), not separate concerns worth their own
// bottom-nav slots.
class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Teachers'),
              Tab(text: 'Children'),
              Tab(text: 'Classes'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                ManageTeachersScreen(),
                ManageChildrenScreen(),
                ManageClassesScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
