import 'package:flutter/material.dart';
import '../../core/models/app_user.dart';

// A form control for assigning teachers to a class: the current selection as
// deletable chips, plus an "Add teacher" dropdown of the teachers not yet
// picked. Stateless -- it renders `selectedIds` and reports every change back
// through `onChanged` with the full new list; the parent owns the state.
class TeacherMultiSelect extends StatelessWidget {
  const TeacherMultiSelect({
    super.key,
    required this.allTeachers,
    required this.selectedIds,
    required this.onChanged,
  });

  final List<AppUser> allTeachers;
  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;

  String _nameFor(String id) => allTeachers
      .firstWhere(
        (t) => t.id == id,
        orElse: () => AppUser(
          id: id,
          role: 'teacher',
          name: 'Unknown teacher',
          phone: '',
          centerId: '',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          createdBy: null,
          updatedBy: null,
        ),
      )
      .name;

  @override
  Widget build(BuildContext context) {
    final unselected =
        allTeachers.where((t) => !selectedIds.contains(t.id)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedIds.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final id in selectedIds)
                Chip(
                  label: Text(_nameFor(id)),
                  onDeleted: () =>
                      onChanged([...selectedIds]..remove(id)),
                ),
            ],
          ),
        const SizedBox(height: 8),
        DropdownButton<String>(
          isExpanded: true,
          hint: const Text('Add teacher'),
          value: null,
          items: [
            for (final t in unselected)
              DropdownMenuItem(value: t.id, child: Text(t.name)),
          ],
          onChanged: unselected.isEmpty
              ? null
              : (id) {
                  if (id != null) onChanged([...selectedIds, id]);
                },
        ),
      ],
    );
  }
}
