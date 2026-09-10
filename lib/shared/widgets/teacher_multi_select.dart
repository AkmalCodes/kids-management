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
        // Measure the field's width via GlobalKey and post-frame callback to
        // pass it to DropdownButton.menuWidth. This makes the popup menu match
        // the field width instead of overhanging it. GlobalKey avoids the
        // "does not support returning intrinsic dimensions" error from
        // AlertDialog's IntrinsicWidth measurement.
        _TeacherDropdownMeasurer(
          onChanged: onChanged,
          selectedIds: selectedIds,
          unselected: unselected,
        ),
      ],
    );
  }
}

// Measures the dropdown's width and passes it to DropdownButton.menuWidth.
class _TeacherDropdownMeasurer extends StatefulWidget {
  const _TeacherDropdownMeasurer({
    required this.onChanged,
    required this.selectedIds,
    required this.unselected,
  });

  final ValueChanged<List<String>> onChanged;
  final List<String> selectedIds;
  final List<AppUser> unselected;

  @override
  State<_TeacherDropdownMeasurer> createState() =>
      _TeacherDropdownMeasurerState();
}

class _TeacherDropdownMeasurerState extends State<_TeacherDropdownMeasurer> {
  final _key = GlobalKey();
  double? _width;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final w = _key.currentContext?.size?.width;
      if (w != null && w != _width && mounted) setState(() => _width = w);
    });
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(
        key: _key,
        child: DropdownButton<String>(
          isExpanded: true,
          menuWidth: _width,
          hint: const Text('Add teacher'),
          value: null,
          items: [
            for (final t in widget.unselected)
              DropdownMenuItem(value: t.id, child: Text(t.name)),
          ],
          onChanged: widget.unselected.isEmpty
              ? null
              : (id) {
                  if (id != null) {
                    widget.onChanged([...widget.selectedIds, id]);
                  }
                },
        ),
      );
}
