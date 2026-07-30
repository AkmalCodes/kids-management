import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// One detail field that shows either a read-only row (when viewing) or a
// text input (when editing), cross-fading between the two. Used on the
// child/class/person detail screens so all three share the same
// view-then-edit behaviour without triplicating it.
//
// In read-only mode a `copyable` field (email/phone) copies its value to the
// clipboard when tapped and shows a "Copied" snackbar; an empty value shows
// a muted "Not provided" instead.
class EditableField extends StatelessWidget {
  const EditableField({
    super.key,
    required this.label,
    required this.controller,
    required this.editing,
    this.keyboardType,
    this.maxLines = 1,
    this.copyable = false,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final bool editing;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool copyable;
  final String? Function(String?)? validator;

  Future<void> _copy(BuildContext context) async {
    final value = controller.text.trim();
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied $label to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      // Distinct keys so the switcher treats view/edit as different children
      // and actually cross-fades between them.
      child: editing
          ? Padding(
              key: const ValueKey('edit'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: TextFormField(
                controller: controller,
                keyboardType: keyboardType,
                maxLines: maxLines,
                decoration: InputDecoration(labelText: label),
                validator: validator,
              ),
            )
          : _ReadOnlyRow(
              key: const ValueKey('view'),
              label: label,
              value: controller.text.trim(),
              copyable: copyable,
              onCopy: copyable ? () => _copy(context) : null,
            ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({
    super.key,
    required this.label,
    required this.value,
    required this.copyable,
    this.onCopy,
  });

  final String label;
  final String value;
  final bool copyable;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValue = value.isNotEmpty;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor)),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  hasValue ? value : 'Not provided',
                  style: hasValue
                      ? theme.textTheme.bodyLarge
                      : theme.textTheme.bodyLarge?.copyWith(color: theme.disabledColor),
                ),
              ),
              // Only a filled, copyable field gets the copy affordance.
              if (copyable && hasValue)
                Icon(Icons.copy_outlined, size: 18, color: theme.hintColor),
            ],
          ),
        ],
      ),
    );
    // Tapping a copyable row copies; other rows are inert.
    return copyable && hasValue
        ? InkWell(onTap: onCopy, child: row)
        : row;
  }
}
