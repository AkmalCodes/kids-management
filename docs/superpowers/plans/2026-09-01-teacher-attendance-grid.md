# Teacher Attendance Grid Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the teacher's single-column list of expand-in-place attendance cards with a four-per-row grid of avatars carrying a status badge, backed by a new full-screen detail screen.

**Architecture:** A presentational `AttendanceGridTile` renders one child — square avatar, translucent pink border, status badge — and knows nothing about controllers. `ChildAttendanceDetailScreen` receives everything the expanded card used to hold and owns the writes for one child. `MarkAttendanceScreen` shrinks to a roster, a search box, a grid, and a long-press menu.

**Tech Stack:** Flutter, Riverpod 2.x, mocktail for tests, existing `AttendanceController` / `ChildController` / `PhotoCaptureController`.

**Spec:** `docs/superpowers/specs/2026-09-01-teacher-attendance-grid-design.md`

## Global Constraints

- Four tiles per row.
- Badges: `present` → green check, `absent` → red cancel, **anything else including no record** → amber question mark. `late` and `excused` are unreachable from this UI and render amber; do **not** invent icons for them and do **not** add values to `AttendanceStatus`.
- The tile border is `colorScheme.primary` at low opacity — translucent, matching the theme. Never a hard outline colour.
- The status badge is inset from the bottom-right corner with padding, so it floats over the avatar rather than touching the edge.
- Allergies appear in the detail screen's identity strip whenever `child.allergies` is non-empty, **and** inside the collapsible.
- The child-details collapsible is **read-only**. RLS restricts `children` writes to directors; an edit affordance could only fail.
- Existing behaviour that must survive unchanged: the search box, and `_todayDate` being captured once at screen construction (a mark made near midnight must not target a different day than the one on screen).
- The full Flutter suite is 208 tests and must stay green.
- Do not add a `Co-Authored-By` trailer to commits.

---

### Task 1: `AttendanceGridTile`

A presentational widget: one child, one optional attendance record, two callbacks. No controllers, no Riverpod reads beyond the avatar's own provider, so it is testable without mocking a data layer.

**Files:**
- Create: `lib/features/teacher/widgets/attendance_grid_tile.dart`
- Test: `test/features/teacher/widgets/attendance_grid_tile_test.dart`

**Interfaces:**
- Consumes: `Child`, `Attendance`, `AttendanceStatus` from `core/models`; `SignedAvatar` and `signedChildAvatarUrlProvider`.
- Produces:
  - `AttendanceGridTile({required Child child, required Attendance? attendance, required VoidCallback onTap, required VoidCallback onLongPress})`
  - Badge icon keys for tests: `Key('status-badge-present')`, `Key('status-badge-absent')`, `Key('status-badge-unmarked')`.

- [ ] **Step 1: Write the failing test**

Create `test/features/teacher/widgets/attendance_grid_tile_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/models/attendance.dart';
import 'package:kids_management/core/models/child.dart';
import 'package:kids_management/features/teacher/widgets/attendance_grid_tile.dart';

Child _child({String name = 'Alice', String? avatarPath}) => Child(
  id: 'child-1',
  name: name,
  dob: DateTime(2022, 1, 1),
  centerId: 'center-1',
  className: 'Sunflower',
  teacherId: 'teacher-1',
  allergies: '',
  notes: '',
  avatarPath: avatarPath,
  enrolledAt: DateTime(2026),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

Attendance _attendance(AttendanceStatus status) => Attendance(
  id: 'att-1',
  childId: 'child-1',
  centerId: 'center-1',
  date: '2026-09-01',
  status: status,
  notes: '',
  photoPath: null,
  belongingsPhotoPath: null,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'teacher-1',
  updatedBy: 'teacher-1',
);

Future<void> _pump(
  WidgetTester tester, {
  Attendance? attendance,
  VoidCallback? onTap,
  VoidCallback? onLongPress,
}) =>
    tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AttendanceGridTile(
              child: _child(),
              attendance: attendance,
              onTap: onTap ?? () {},
              onLongPress: onLongPress ?? () {},
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('shows the child name', (tester) async {
    await _pump(tester);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('a present record shows the present badge', (tester) async {
    await _pump(tester, attendance: _attendance(AttendanceStatus.present));
    expect(find.byKey(const Key('status-badge-present')), findsOneWidget);
    expect(find.byKey(const Key('status-badge-absent')), findsNothing);
    expect(find.byKey(const Key('status-badge-unmarked')), findsNothing);
  });

  testWidgets('an absent record shows the absent badge', (tester) async {
    await _pump(tester, attendance: _attendance(AttendanceStatus.absent));
    expect(find.byKey(const Key('status-badge-absent')), findsOneWidget);
  });

  testWidgets('no record shows the unmarked badge', (tester) async {
    await _pump(tester, attendance: null);
    expect(find.byKey(const Key('status-badge-unmarked')), findsOneWidget);
  });

  testWidgets('late and excused fall back to the unmarked badge', (tester) async {
    // The UI can only ever set present or absent, so these are unreachable
    // from here. They render as unmarked rather than inventing an icon for a
    // state a teacher cannot produce.
    await _pump(tester, attendance: _attendance(AttendanceStatus.late));
    expect(find.byKey(const Key('status-badge-unmarked')), findsOneWidget);

    await _pump(tester, attendance: _attendance(AttendanceStatus.excused));
    expect(find.byKey(const Key('status-badge-unmarked')), findsOneWidget);
  });

  testWidgets('tap and long-press fire their callbacks', (tester) async {
    var taps = 0;
    var longPresses = 0;
    await _pump(tester, onTap: () => taps++, onLongPress: () => longPresses++);

    await tester.tap(find.byType(AttendanceGridTile));
    await tester.pump();
    expect(taps, 1);
    expect(longPresses, 0);

    await tester.longPress(find.byType(AttendanceGridTile));
    await tester.pump();
    expect(longPresses, 1);
    expect(taps, 1);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/teacher/widgets/attendance_grid_tile_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'kids_management/features/teacher/widgets/attendance_grid_tile.dart'` (the file does not exist yet).

- [ ] **Step 3: Write the implementation**

Create `lib/features/teacher/widgets/attendance_grid_tile.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/child.dart';
import '../../../core/controllers/child_controller.dart';
import '../../../shared/widgets/signed_avatar.dart';

// One child in the attendance grid: avatar, name, and a badge showing today's
// status. Purely presentational -- it takes the record it should render and
// two callbacks, and performs no writes. That keeps the marking logic in one
// place (MarkAttendanceScreen) and makes this widget testable on its own.
class AttendanceGridTile extends ConsumerWidget {
  const AttendanceGridTile({
    super.key,
    required this.child,
    required this.attendance,
    required this.onTap,
    required this.onLongPress,
  });

  final Child child;

  // Null means no record exists for today, which is a real and important
  // state: it is how a teacher sees who is still outstanding.
  final Attendance? attendance;

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                // Translucent so it reads as part of the palette rather than
                // a hard outline around every child.
                border: Border.all(color: colors.primary.withValues(alpha: 0.25), width: 2),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Center(
                        child: SignedAvatar(
                          urlProvider: child.avatarPath == null
                              ? null
                              : signedChildAvatarUrlProvider(child.avatarPath!),
                          radius: 34,
                        ),
                      ),
                    ),
                  ),
                  // Inset rather than flush to the corner, so the badge floats
                  // over the avatar instead of colliding with its rounded edge.
                  Positioned(right: 6, bottom: 6, child: _badge(colors)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            child.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  // present/absent are the only statuses this UI can set. Anything else --
  // including late and excused, which exist in the enum but have never been
  // offered -- renders as unmarked rather than inventing an icon for a state
  // a teacher cannot produce.
  Widget _badge(ColorScheme colors) {
    final (key, icon, color) = switch (attendance?.status) {
      AttendanceStatus.present =>
        (const Key('status-badge-present'), Icons.check_circle, Colors.green.shade600),
      AttendanceStatus.absent =>
        (const Key('status-badge-absent'), Icons.cancel, Colors.red.shade600),
      _ => (
          const Key('status-badge-unmarked'),
          Icons.help,
          Colors.amber.shade700,
        ),
    };

    return Container(
      key: key,
      decoration: BoxDecoration(color: colors.surface, shape: BoxShape.circle),
      padding: const EdgeInsets.all(1),
      child: Icon(icon, size: 20, color: color),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/teacher/widgets/attendance_grid_tile_test.dart`
Expected: PASS — 6 tests.

- [ ] **Step 5: Run analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/teacher/widgets/attendance_grid_tile.dart test/features/teacher/widgets/attendance_grid_tile_test.dart
git commit -m "feat(teacher): attendance grid tile with status badge"
```

---

### Task 2: `ChildAttendanceDetailScreen`

Everything the expanded card holds, full-screen, plus a read-only collapsible of the child's details and an always-visible allergy chip.

**Files:**
- Create: `lib/features/teacher/screens/child_attendance_detail_screen.dart`
- Test: `test/features/teacher/screens/child_attendance_detail_screen_test.dart`
- Reference (do not modify yet): `lib/features/teacher/screens/mark_attendance_screen.dart:250-300` for the photo-slot helpers being moved

**Interfaces:**
- Consumes: `AttendanceGridTile` is not used here. Uses `AttendanceController.markAttendance` / `attachPhoto` / `getSignedPhotoUrl`, `PhotoCaptureController`, `SignedPhotoThumbnail`, `AppLoader`.
- Produces:
  - `ChildAttendanceDetailScreen({required Child child, required String date, required Attendance? initialAttendance, required ValueChanged<Attendance> onChanged})`
  - `onChanged` fires with every saved record so the grid updates without re-fetching.

- [ ] **Step 1: Write the failing test**

Create `test/features/teacher/screens/child_attendance_detail_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kids_management/core/auth/auth_controller.dart';
import 'package:kids_management/core/models/app_user.dart';
import 'package:kids_management/core/models/attendance.dart';
import 'package:kids_management/core/models/child.dart';
import 'package:kids_management/core/controllers/attendance_controller.dart';
import 'package:kids_management/core/controllers/photo_capture_controller.dart';
import 'package:kids_management/features/teacher/screens/child_attendance_detail_screen.dart';

class MockAttendanceController extends Mock implements AttendanceController {}

class MockPhotoCaptureController extends Mock implements PhotoCaptureController {}

AppUser _teacher() => AppUser(
  id: 'teacher-1',
  role: 'teacher',
  name: 'Teacher',
  phone: '',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

Child _child({String allergies = ''}) => Child(
  id: 'child-1',
  name: 'Alice',
  dob: DateTime(2022, 1, 1),
  centerId: 'center-1',
  className: 'Sunflower',
  teacherId: 'teacher-1',
  allergies: allergies,
  notes: 'Naps after lunch',
  enrolledAt: DateTime(2026),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

Attendance _saved(AttendanceStatus status) => Attendance(
  id: 'att-1',
  childId: 'child-1',
  centerId: 'center-1',
  date: '2026-09-01',
  status: status,
  notes: '',
  photoPath: null,
  belongingsPhotoPath: null,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'teacher-1',
  updatedBy: 'teacher-1',
);

void main() {
  setUpAll(() {
    registerFallbackValue(AttendanceStatus.present);
    registerFallbackValue(XFile(''));
  });

  late MockAttendanceController mockAttendance;
  late MockPhotoCaptureController mockPhotoCapture;

  setUp(() {
    mockAttendance = MockAttendanceController();
    mockPhotoCapture = MockPhotoCaptureController();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Child? child,
    Attendance? initial,
    ValueChanged<Attendance>? onChanged,
  }) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(_teacher())),
            attendanceControllerProvider.overrideWithValue(mockAttendance),
            photoCaptureControllerProvider.overrideWithValue(mockPhotoCapture),
          ],
          child: MaterialApp(
            home: ChildAttendanceDetailScreen(
              child: child ?? _child(),
              date: '2026-09-01',
              initialAttendance: initial,
              onChanged: onChanged ?? (_) {},
            ),
          ),
        ),
      );

  testWidgets('shows the allergy chip when the child has allergies',
      (tester) async {
    await pumpScreen(tester, child: _child(allergies: 'Peanuts'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('allergy-chip')), findsOneWidget);
    expect(find.textContaining('Peanuts'), findsWidgets);
  });

  testWidgets('omits the allergy chip when there are no allergies',
      (tester) async {
    await pumpScreen(tester, child: _child());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('allergy-chip')), findsNothing);
  });

  testWidgets('child details start collapsed and expand on tap', (tester) async {
    await pumpScreen(tester, child: _child());
    await tester.pumpAndSettle();

    expect(find.text('Naps after lunch'), findsNothing);

    await tester.tap(find.text('Child details'));
    await tester.pumpAndSettle();

    expect(find.text('Naps after lunch'), findsOneWidget);
    expect(find.text('Sunflower'), findsWidgets);
  });

  testWidgets('marking present saves and reports the new record',
      (tester) async {
    Attendance? reported;
    when(() => mockAttendance.markAttendance(
          childId: any(named: 'childId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          status: any(named: 'status'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
          notes: any(named: 'notes'),
        )).thenAnswer((_) async => _saved(AttendanceStatus.present));

    await pumpScreen(tester, onChanged: (a) => reported = a);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();

    verify(() => mockAttendance.markAttendance(
          childId: 'child-1',
          centerId: 'center-1',
          date: '2026-09-01',
          status: AttendanceStatus.present,
          actorUid: 'teacher-1',
          existingId: null,
        )).called(1);
    expect(reported?.status, AttendanceStatus.present);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/teacher/screens/child_attendance_detail_screen_test.dart`
Expected: FAIL — cannot resolve `child_attendance_detail_screen.dart`.

- [ ] **Step 3: Write the implementation**

Create `lib/features/teacher/screens/child_attendance_detail_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/child.dart';
import '../../../core/controllers/attendance_controller.dart';
import '../../../core/controllers/child_controller.dart';
import '../../../core/controllers/photo_capture_controller.dart';
import '../../../shared/util/date_display.dart';
import '../../../shared/widgets/signed_avatar.dart';
import '../../../shared/widgets/signed_photo_thumbnail.dart';

enum _PhotoAction { camera, gallery, delete }

// One child's attendance for one day. This holds everything the old
// expand-in-place card on MarkAttendanceScreen held -- status, both photos,
// notes -- at a size where it is actually usable, plus a read-only summary of
// the child.
//
// It owns the writes for this child and reports each saved record back through
// onChanged, so the grid behind it updates without re-fetching the roster.
class ChildAttendanceDetailScreen extends ConsumerStatefulWidget {
  const ChildAttendanceDetailScreen({
    super.key,
    required this.child,
    required this.date,
    required this.initialAttendance,
    required this.onChanged,
  });

  final Child child;
  final String date;
  final Attendance? initialAttendance;
  final ValueChanged<Attendance> onChanged;

  @override
  ConsumerState<ChildAttendanceDetailScreen> createState() =>
      _ChildAttendanceDetailScreenState();
}

class _ChildAttendanceDetailScreenState
    extends ConsumerState<ChildAttendanceDetailScreen> {
  late Attendance? _attendance = widget.initialAttendance;
  late final TextEditingController _notes =
      TextEditingController(text: widget.initialAttendance?.notes ?? '');
  bool _detailsExpanded = false;
  bool _busy = false;

  static const _statusChoices = [AttendanceStatus.present, AttendanceStatus.absent];

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  // Every write funnels through here so the local copy, the parent grid and
  // the notes field never disagree about what was saved.
  void _apply(Attendance updated) {
    setState(() {
      _attendance = updated;
    });
    widget.onChanged(updated);
  }

  Future<void> _setStatus(AttendanceStatus status) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;
    setState(() {
      _busy = true;
    });
    try {
      final updated = await ref.read(attendanceControllerProvider).markAttendance(
            childId: widget.child.id,
            centerId: widget.child.centerId,
            date: widget.date,
            status: status,
            actorUid: user.id,
            existingId: _attendance?.id,
          );
      _apply(updated);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = widget.child;
    final current = _attendance;

    return Scaffold(
      appBar: AppBar(title: Text(child.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _identityStrip(theme, child),
          const Divider(height: 32),
          Text(isoWithWeekday(widget.date), style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Text('Status', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final status in _statusChoices)
                ChoiceChip(
                  label: Text(_statusLabel(status)),
                  selected: current?.status == status,
                  onSelected: _busy ? null : (_) => _setStatus(status),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _photoRow(current),
          const SizedBox(height: 20),
          Text('Notes', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Anything to pass on?'),
          ),
          const Divider(height: 32),
          _childDetails(theme, child),
        ],
      ),
    );
  }

  Widget _identityStrip(ThemeData theme, Child child) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SignedAvatar(
          urlProvider: child.avatarPath == null
              ? null
              : signedChildAvatarUrlProvider(child.avatarPath!),
          radius: 32,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(child.name, style: theme.textTheme.titleLarge),
              if (child.className.isNotEmpty)
                Text(child.className, style: theme.textTheme.bodyMedium),
              // Always visible, never behind the collapse: allergy information
              // can be needed immediately and a teacher should not have to know
              // to go looking for it.
              if (child.allergies.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Chip(
                  key: const Key('allergy-chip'),
                  avatar: const Icon(Icons.warning_amber, size: 18),
                  label: Text(child.allergies),
                  backgroundColor: theme.colorScheme.errorContainer,
                  side: BorderSide.none,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // Read-only on purpose: RLS restricts children writes to directors, so an
  // edit affordance here could only ever produce a failure.
  Widget _childDetails(ThemeData theme, Child child) {
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: const Text('Child details'),
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: _detailsExpanded,
        onExpansionChanged: (v) => setState(() => _detailsExpanded = v),
        children: [
          _detailRow(theme, 'Date of birth', '${_formatDate(child.dob)}  •  Age ${_age(child.dob)}'),
          if (child.className.isNotEmpty) _detailRow(theme, 'Class', child.className),
          if (child.allergies.trim().isNotEmpty)
            _detailRow(theme, 'Allergies', child.allergies),
          if (child.notes.trim().isNotEmpty) _detailRow(theme, 'Notes', child.notes),
        ],
      ),
    );
  }

  Widget _detailRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _photoRow(Attendance? current) {
    return Row(
      children: [
        Expanded(
          child: _photoSlotWithLabel(
            key: const Key('checkin-photo'),
            label: 'Check-in photo',
            photoPath: current?.photoPath,
            onTap: current == null ? null : () => _photoMenu(current, isBelongings: false),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _photoSlotWithLabel(
            key: const Key('belongings-photo'),
            label: 'Belongings',
            photoPath: current?.belongingsPhotoPath,
            onTap: current == null ? null : () => _photoMenu(current, isBelongings: true),
          ),
        ),
      ],
    );
  }

  Widget _photoSlotWithLabel({
    required Key key,
    required String label,
    required String? photoPath,
    required VoidCallback? onTap,
  }) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 96,
            child: photoPath == null
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: const Center(child: Icon(Icons.add_a_photo_outlined)),
                  )
                : SignedPhotoThumbnail(photoPath: photoPath, radius: 48),
          ),
        ),
      ],
    );
  }

  // A photo can only hang off an existing attendance row, so the slots stay
  // disabled until a status has been set. Both photos are optional and
  // independent of each other and of the status.
  //
  // Saving is two steps by design: upload the file to the private bucket, then
  // write the returned Storage path onto the row. The controller exposes them
  // separately, so a failed attach cannot leave a half-written row pointing at
  // nothing.
  Future<void> _pickAndSavePhoto(
    Attendance record, {
    required bool isBelongings,
    required bool fromGallery,
  }) async {
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;
    final capture = ref.read(photoCaptureControllerProvider);
    final photo = fromGallery
        ? await capture.pickFromGallery()
        : await capture.captureFromCamera();
    if (photo == null) return;

    final service = ref.read(attendanceControllerProvider);
    final Attendance updated;
    if (isBelongings) {
      final path = await service.uploadBelongingsPhoto(
        childId: widget.child.id,
        date: widget.date,
        photo: photo,
      );
      updated = await service.attachBelongingsPhoto(
        id: record.id,
        belongingsPhotoPath: path,
        actorUid: user.id,
      );
    } else {
      final path = await service.uploadCheckInPhoto(
        childId: widget.child.id,
        date: widget.date,
        photo: photo,
      );
      updated = await service.attachCheckInPhoto(
        id: record.id,
        photoPath: path,
        actorUid: user.id,
      );
    }
    _apply(updated);
  }

  // Camera / gallery / delete, matching what the expanded card offered.
  Future<void> _photoMenu(Attendance record, {required bool isBelongings}) async {
    final hasPhoto = isBelongings
        ? record.belongingsPhotoPath != null
        : record.photoPath != null;

    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(sheetContext).pop(_PhotoAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(sheetContext).pop(_PhotoAction.gallery),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () => Navigator.of(sheetContext).pop(_PhotoAction.delete),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    final user = ref.read(currentUserProvider).value;
    if (user == null) return;
    final service = ref.read(attendanceControllerProvider);

    switch (action) {
      case _PhotoAction.camera:
        await _pickAndSavePhoto(record, isBelongings: isBelongings, fromGallery: false);
      case _PhotoAction.gallery:
        await _pickAndSavePhoto(record, isBelongings: isBelongings, fromGallery: true);
      case _PhotoAction.delete:
        final updated = isBelongings
            ? await service.removeBelongingsPhoto(
                id: record.id,
                belongingsPhotoPath: record.belongingsPhotoPath!,
                actorUid: user.id,
              )
            : await service.removeCheckInPhoto(
                id: record.id,
                photoPath: record.photoPath!,
                actorUid: user.id,
              );
        _apply(updated);
    }
  }

  static String _statusLabel(AttendanceStatus status) => switch (status) {
        AttendanceStatus.present => 'Present',
        AttendanceStatus.absent => 'Absent',
        AttendanceStatus.late => 'Late',
        AttendanceStatus.excused => 'Excused',
      };

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static int _age(DateTime dob) {
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }
}
```

- [ ] **Step 4: Confirm the controller signatures used above are the real ones**

The code above calls these exact members. Verify each exists with that signature before running the tests — a mismatch here fails at compile time, not at runtime:

Run: `grep -n "captureFromCamera\|pickFromGallery" lib/core/controllers/photo_capture_controller.dart`
Expected: `Future<XFile?> captureFromCamera()` and `Future<XFile?> pickFromGallery()`

Run: `grep -n "uploadCheckInPhoto\|uploadBelongingsPhoto\|attachCheckInPhoto\|attachBelongingsPhoto\|removeCheckInPhoto\|removeBelongingsPhoto" lib/core/controllers/attendance_controller.dart`
Expected: all six exist. Their named parameters are:
- `uploadCheckInPhoto({childId, date, photo})` → `Future<String>` (the Storage path)
- `uploadBelongingsPhoto({childId, date, photo})` → `Future<String>`
- `attachCheckInPhoto({id, photoPath, actorUid})` → `Future<Attendance>`
- `attachBelongingsPhoto({id, belongingsPhotoPath, actorUid})` → `Future<Attendance>`
- `removeCheckInPhoto({id, photoPath, actorUid})` → `Future<Attendance>`
- `removeBelongingsPhoto({id, belongingsPhotoPath, actorUid})` → `Future<Attendance>`

Note `id` is the **attendance row's** id, not the child's.

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/features/teacher/screens/child_attendance_detail_screen_test.dart`
Expected: PASS — 4 tests.

- [ ] **Step 6: Run analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/features/teacher/screens/child_attendance_detail_screen.dart test/features/teacher/screens/child_attendance_detail_screen_test.dart
git commit -m "feat(teacher): full-screen attendance detail with collapsible child details"
```

---

### Task 3: Rework `MarkAttendanceScreen` into a grid

**Files:**
- Modify: `lib/features/teacher/screens/mark_attendance_screen.dart`
- Modify: `test/features/teacher/screens/mark_attendance_screen_test.dart`

**Interfaces:**
- Consumes: `AttendanceGridTile` (Task 1), `ChildAttendanceDetailScreen` (Task 2).
- Produces: nothing new. `MarkAttendanceScreen`'s public constructor is unchanged.

- [ ] **Step 1: Rewrite the screen's tests**

Replace the existing `testWidgets('shows roster and marks attendance on tap', …)` — which asserts the old expand-in-place behaviour — with the tests below. **Keep** the existing `'shows a message when the teacher has no children assigned'` test unchanged, and keep the file's existing imports, mock classes, `_teacher()`, `_child()` and `pumpScreen` helpers.

Add these imports to the file:

```dart
import 'package:kids_management/features/teacher/widgets/attendance_grid_tile.dart';
import 'package:kids_management/features/teacher/screens/child_attendance_detail_screen.dart';
```

Add these tests inside `main()`:

```dart
  testWidgets('renders one grid tile per child', (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer(
      (_) async => [_child(id: 'child-1', name: 'Alice'), _child(id: 'child-2', name: 'Bob')],
    );
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.byType(AttendanceGridTile), findsNTimes(2));
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('a child with no record today shows the unmarked badge',
      (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('status-badge-unmarked')), findsOneWidget);
  });

  testWidgets('long-press then Mark present saves and updates the badge',
      (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => []);
    when(() => mockAttendance.markAttendance(
          childId: any(named: 'childId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          status: any(named: 'status'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
          notes: any(named: 'notes'),
        )).thenAnswer(
      (_) async => Attendance(
        id: 'att-1',
        childId: 'child-1',
        centerId: 'center-1',
        date: '2026-09-01',
        status: AttendanceStatus.present,
        notes: '',
        photoPath: null,
        belongingsPhotoPath: null,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        createdBy: 'teacher-1',
        updatedBy: 'teacher-1',
      ),
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(AttendanceGridTile));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark present'));
    await tester.pumpAndSettle();

    verify(() => mockAttendance.markAttendance(
          childId: 'child-1',
          centerId: 'center-1',
          date: any(named: 'date'),
          status: AttendanceStatus.present,
          actorUid: 'teacher-1',
          existingId: null,
        )).called(1);

    // The write's returned row is applied locally rather than re-fetched, so
    // the badge must change without fetchForDate being called again.
    expect(find.byKey(const Key('status-badge-present')), findsOneWidget);
    verify(() => mockAttendance.fetchForDate(any())).called(1);
  });

  testWidgets('tapping a tile opens the detail screen', (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForDate(any())).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AttendanceGridTile));
    await tester.pumpAndSettle();

    expect(find.byType(ChildAttendanceDetailScreen), findsOneWidget);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/teacher/screens/mark_attendance_screen_test.dart`
Expected: FAIL — `AttendanceGridTile` is not built by the screen yet, so `findsNTimes(2)` finds none.

- [ ] **Step 3: Replace the list with a grid**

In `lib/features/teacher/screens/mark_attendance_screen.dart`:

Add imports:

```dart
import '../widgets/attendance_grid_tile.dart';
import 'child_attendance_detail_screen.dart';
```

Replace the `ListView.builder(...)` in the roster body with:

```dart
              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 16,
                  // Taller than wide: the tile is a square avatar plus a name
                  // line beneath it.
                  childAspectRatio: 0.78,
                ),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final child = visible[index];
                  final existing = data.attendanceByChild[child.id];
                  return AttendanceGridTile(
                    child: child,
                    attendance: existing,
                    onTap: () => _openDetail(child, existing),
                    onLongPress: () => _showActions(child, existing),
                  );
                },
              );
```

Add these two methods to `_MarkAttendanceScreenState`:

```dart
  Future<void> _openDetail(Child child, Attendance? existing) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChildAttendanceDetailScreen(
          child: child,
          date: _today,
          initialAttendance: existing,
          // The detail screen reports every save back, so the grid behind it
          // is already correct when the user returns -- no re-fetch, no flash
          // of stale badges.
          onChanged: (updated) => _applyUpdate(child.id, updated),
        ),
      ),
    );
  }

  // Long-press is the shortcut for the common case. Everything reachable here
  // is also reachable by tapping through to the detail screen, so the gesture
  // being undiscoverable costs nothing.
  Future<void> _showActions(Child child, Attendance? existing) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Open details'),
              onTap: () => Navigator.of(sheetContext).pop('details'),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Mark present'),
              onTap: () => Navigator.of(sheetContext).pop('present'),
            ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: const Text('Mark absent'),
              onTap: () => Navigator.of(sheetContext).pop('absent'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'details':
        await _openDetail(child, existing);
      case 'present':
        await _setStatus(child, AttendanceStatus.present, existing);
      case 'absent':
        await _setStatus(child, AttendanceStatus.absent, existing);
    }
  }
```

- [ ] **Step 4: Delete the card and everything only it used**

Remove from `mark_attendance_screen.dart`:
- `_childCard`
- `_expandedChildId` and `_toggleExpanded`
- `_avatar` (the grid tile draws its own)
- `_photoSlot`, `_photoSlotWithLabel`, `_PhotoAction`, and the photo/notes handlers that only the expanded card called — these now live on the detail screen
- `_statusChoices` and `_statusLabel` if nothing else references them

**Keep** `_setStatus` and `_applyUpdate` — the long-press menu uses both.

Then confirm nothing dangles:

Run: `flutter analyze`
Expected: `No issues found!` — any "unused element" warning here means something was left behind; delete it rather than silencing it.

- [ ] **Step 5: Run the screen's tests**

Run: `flutter test test/features/teacher/screens/mark_attendance_screen_test.dart`
Expected: PASS — 5 tests (the retained empty-roster test plus the four new ones).

- [ ] **Step 6: Run the full suite**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and `All tests passed!`. The count should be 208 minus the removed expand-card test plus the new ones — report the actual number, do not assume it.

- [ ] **Step 7: Commit**

```bash
git add lib/features/teacher/screens/mark_attendance_screen.dart test/features/teacher/screens/mark_attendance_screen_test.dart
git commit -m "feat(teacher): replace attendance list with a grid"
```

---

### Task 4: Update the design docs

**Files:**
- Modify: `docs/superpowers/specs/2026-07-01-childcare-management-design.md`

- [ ] **Step 1: Update the attendance section**

Find the §6 attendance description (search for `attendance` near the teacher feature list) and update it to say the teacher's Attendance tab is a four-per-row grid of children with status badges, that tapping opens `ChildAttendanceDetailScreen` and long-press offers mark-present/mark-absent, and that allergies are surfaced on the detail screen.

Note the two deferred items with their blockers, so the next person does not rediscover them:
- staff attendance needs a table (`attendance` is `child_id NOT NULL`, `UNIQUE (child_id, date)`)
- teacher access to parent contacts is blocked by `profiles_select` and `children_parents_select`

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-07-01-childcare-management-design.md
git commit -m "docs: teacher attendance grid in the design spec"
```

---

## Done when

- `flutter analyze` is clean and the full suite passes.
- The teacher's Attendance tab shows a four-per-row grid; every child carries a green, red or amber badge.
- Long-press marks present or absent without leaving the grid, and the badge changes without a re-fetch.
- Tapping a child opens the detail screen with status, both photos and notes working as they did in the expanded card.
- A child with allergies shows the chip without expanding anything.
- `_childCard` and `_expandedChildId` no longer exist.
