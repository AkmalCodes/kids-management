# Screen Map — KawanKecil

A quick reference to every screen in the app so we can name the same thing when discussing UI/logic changes. Grouped by area. File paths are relative to `lib/`.

For deeper behaviour, data model, and RLS details, see the design spec: [`2026-07-01-childcare-management-design.md`](2026-07-01-childcare-management-design.md). This file is the "what screens exist and how you get to them" index; keep it in sync when screens are added, removed, or renamed.

---

## Entry & routing (no visible chrome of their own)

| Name | File | What it does |
|---|---|---|
| **AuthGate** | `core/auth/auth_gate.dart` | The app's root gate. Decides: not signed in → LoginScreen; a password-recovery link is active → SetPasswordScreen (recovery); an invited account that hasn't set a password → SetPasswordScreen (invite); otherwise → RoleRouter. |
| **RoleRouter** | `core/auth/role_router.dart` | Reads the signed-in user's `role` and shows the matching shell: parent → ParentShell, teacher → TeacherShell, director → DirectorShell. |

---

## Auth screens

| Name | File | How you reach it | What's on it |
|---|---|---|---|
| **LoginScreen** | `features/auth/login_screen.dart` | Default when signed out | Email + password fields, Sign In, and a **"Forgot password?"** link. |
| **ForgotPasswordScreen** | `features/auth/forgot_password_screen.dart` | "Forgot password?" on LoginScreen | Enter email → sends a reset link; shows a confirmation message. |
| **SetPasswordScreen** | `features/auth/set_password_screen.dart` | Opening an invite or password-reset email link (deep link) | New password + confirm. Used for both invite completion and password recovery. |

---

## Shells (the bottom-nav container for each role)

Each shell is an AppBar + a bottom `NavigationBar`; the tabs below just swap the body.

| Shell | File | Tabs (in order) |
|---|---|---|
| **ParentShell** | `features/parent/parent_shell.dart` | Schedule · Attendance · Reports *(placeholder)* · Profile |
| **TeacherShell** | `features/teacher/teacher_shell.dart` | Schedule · Attendance · Lessons *(placeholder)* · Reports *(placeholder)* · Profile |
| **DirectorShell** | `features/director/director_shell.dart` | People · Schedule · Lessons *(placeholder)* · Attendance · Profile |

---

## Parent tab screens

| Tab | Name | File | What's on it |
|---|---|---|---|
| Schedule | **ChildScheduleScreen** | `features/parent/screens/child_schedule_screen.dart` | Read-only agenda of the parent's child's **class** schedule (child → class_id). |
| Attendance | **ChildAttendanceScreen** | `features/parent/screens/child_attendance_screen.dart` | The child's attendance history as tappable **cards** (date, status, photo thumbnails). |
| (from a card) | **AttendanceDetailScreen** | `features/parent/screens/attendance_detail_screen.dart` | One day's status + notes + the check-in and belongings photos shown large. |
| Reports | **ChildReportsScreen** | `features/parent/screens/child_reports_screen.dart` | Read-only feed of the child's daily reports (newest first): teacher's note + photo thumbnails. |
| Profile | **ProfileScreen** | see *Profile* below | Shared across all roles. |

---

## Teacher tab screens

| Tab | Name | File | What's on it |
|---|---|---|---|
| Schedule | **TeacherScheduleScreen** | `features/teacher/screens/teacher_schedule_screen.dart` | Editable agenda of the class the teacher is assigned to. Drills into the day view. |
| Attendance | **MarkAttendanceScreen** | `features/teacher/screens/mark_attendance_screen.dart` | Screen design AA1 "arrival board": date + class title, search; counts (here / waiting / absent); a Teachers row (own tile → clock in/out, co-teachers → profile); then WAITING (faded tiles, "Check in"), HERE (badge + arrival time) and ABSENT grids. Tapping a waiting child opens the camera, then the **check-in sheet**; tapping a marked child opens the sheet pre-filled. "Mark the rest…" marks every waiting child absent after a confirm. |
| (from a child) | **AttendanceCheckInSheet** | `features/teacher/widgets/attendance_check_in_sheet.dart` | Bottom sheet (AA2), replaced ChildAttendanceDetailScreen: name, class, allergies warning; check-in photo (retake / gallery / remove); Present·Late·Absent·Excused; belongings photo; note. Save = mark row, then upload/attach photos; each saved step is reported to the grid, a failure keeps the sheet open and a retry updates the same row. |
| Lessons | **TeacherLessonPlansScreen** | `features/teacher/screens/teacher_lesson_plans_screen.dart` | The teacher's own lesson plans (date · subject · status chip); **+** → LessonPlanEditScreen; tap → edit/submit/delete. |
| (from a plan / +) | **LessonPlanEditScreen** | `features/shared_lessons/lesson_plan_edit_screen.dart` | Title, subject, class, content (reusable — no date). Teacher: edit while draft/rejected, **Submit**, delete. Director: edit + **Approve/Reject** any. |
| (from a schedule event) | **LessonPlanViewScreen** | `features/shared_lessons/lesson_plan_view_screen.dart` | Read-only plan (subject/title/content) opened by tapping a schedule event that has an approved plan attached. |
| Reports | **TeacherReportsScreen** | `features/teacher/screens/teacher_reports_screen.dart` | The teacher's class as carded rows, with a **day selector** (‹ › + date picker) and a collapsible **student-name search**; tap a child → DailyReportEditScreen for the selected day. |
| (from a child row) | **DailyReportEditScreen** | `features/teacher/screens/daily_report_edit_screen.dart` | Write/edit today's daily report for one child: free text + photos (add/remove). Opens the existing report or a blank form. |
| Profile | **ProfileScreen** | see *Profile* below | |

---

## Director tab screens

| Tab | Name | File | What's on it |
|---|---|---|---|
| People | **PeopleScreen** | `features/director/screens/people_screen.dart` | Wrapper with **Teachers \| Children \| Classes** sub-tabs. |
| People › Teachers | **ManageTeachersScreen** | `features/director/screens/manage_teachers_screen.dart` | Teacher list; **+** invites a teacher; tap a row → PersonDetailScreen. |
| People › Children | **ManageChildrenScreen** | `features/director/screens/manage_children_screen.dart` | Child list; **+** opens EnrollChildScreen; per-row icon invites a parent; tap a row → ChildDetailScreen; **long-press → Edit/Delete**. |
| People › Classes | **ManageClassesScreen** | `features/director/screens/manage_classes_screen.dart` | Class list (avatar + assigned teacher); **+** creates a class (dialog); tap a row → ClassDetailScreen; **long-press → Edit/Delete**. |
| (from a class row) | **ClassDetailScreen** | `features/director/screens/class_detail_screen.dart` | Opens read-only (AppBar ✏️ toggles edit); photo (class-avatars, tap to zoom), name, teacher. |
| (from Children +) | **EnrollChildScreen** | `features/director/screens/enroll_child_screen.dart` | Create a child record + invite its first parent in one form. |
| (from a child row) | **ChildDetailScreen** | `features/director/screens/child_detail_screen.dart` | Opens read-only (AppBar ✏️ toggles edit): photo (tap to zoom), name, DOB (age shown), **class** (dropdown → class_id, drives the parent schedule), class teacher, allergies, notes + a **Parents** section (name + tap-to-copy email). |
| (from a teacher row / Profile) | **PersonDetailScreen** | `features/profile/person_detail_screen.dart` | Opens read-only (AppBar ✏️ toggles edit): photo (tap to zoom), name, phone + HR/contact details (address, DOB, emergency contact) and a read-only login email; email/phone tap-to-copy. Reused for self-edit (Profile tab) and director-edits-other (People). |
| Schedule | **DirectorSchedulesScreen** | `features/director/screens/director_schedules_screen.dart` | Searchable **class** list → PersonScheduleScreen for that class. |
| (from a class) | **PersonScheduleScreen** | `features/director/screens/person_schedule_screen.dart` | Reusable editable agenda view (type='class'/'teacher'/'child'). |
| Lessons | **DirectorLessonsScreen** | `features/director/screens/director_lessons_screen.dart` | Browse **all** lesson plans; filter by teacher + status; tap → LessonPlanEditScreen (approve/reject/edit). A **Subjects** button → ManageSubjectsScreen. |
| (from Subjects) | **ManageSubjectsScreen** | `features/director/screens/manage_subjects_screen.dart` | Center-defined lesson subjects: list, **+** create, tap to rename/delete. |
| Attendance | **DirectorAttendanceScreen** | `features/director/screens/director_attendance_screen.dart` | Screen design AA4: everyone for a chosen date, **Children | Teachers** switch. Children: counts, a red banner naming teachers who haven't clocked in (→ Teachers), class chips, one section per class ("BUNGA · 8 OF 14 HERE") of read-only tiles; tap → day sheet (status, photos, note — `AttendanceDayDetails`). Teachers: clock times + status per teacher; tap → **StaffAttendanceFixSheet** (status + note; record a *missing* clock-in/out at a picked time after a confirm; recorded times are locked). |
| Profile | **ProfileScreen** | see *Profile* below | |

---

## Profile / account settings (shared by all roles)

| Name | File | How you reach it | What's on it |
|---|---|---|---|
| **ProfileScreen** | `features/profile/profile_screen.dart` | Profile tab in any shell | Avatar (+ Change photo), name/email/role, and buttons: **Profile details**, **Change password**, **Sign out**. |
| **PersonDetailScreen** | `features/profile/person_detail_screen.dart` | "Profile details" on ProfileScreen (self), or a teacher row in People (director) | Edit photo, name, phone. Self-edit vs director-edit-other is decided automatically. |
| **ChangePasswordScreen** | `features/profile/change_password_screen.dart` | "Change password" on ProfileScreen | New password + confirm, while already signed in. |

---

## Shared screens & building-block widgets

Not full "screens" you navigate a bottom-nav to, but reused UI pieces worth naming.

| Name | File | Used by | What it is |
|---|---|---|---|
| **ScheduleAgendaView** | `shared/widgets/schedule_agenda_view.dart` | Schedule screens | The whole Schedule tab (screen design SA): month title + **Today** + date picker; a Mon–Sun week strip (swipe for prev/next week, dots = that day's event colours); a **List | Timeline** toggle showing the selected day as agenda cards (SA1) or the hour grid (SA2, `DayTimetable`). Today: finished events fade, the running one gets **Now**, a pink line marks the time. Tapping an event opens the event sheet; **+** (or an empty timeline hour, editable only) opens it as a blank form. Owns create/edit/delete. For a class, resolves the subject via `class_plan_subjects` so it shows for all roles. |
| **DayTimetable** | `shared/widgets/day_timetable.dart` | ScheduleAgendaView (Timeline) | The hour grid: pale event blocks with a colour bar; with `nowTime` (today) past events fade and a now line shows. Tap-to-add/edit, fade-in on new entries. |
| **ScheduleEventSheet** | `shared/widgets/schedule_event_sheet.dart` | Schedule (tap an event / +) | One bottom sheet for an event. View: time + length, repeat rule, 'Added by you', the attached lesson plan card (opens `LessonPlanViewScreen`); Edit/Delete for its creator or a director (delete confirmed). Edit swaps the summary for the form in place (Cancel returns to the summary); + opens it straight in the form. Form: name, Starts/Ends tiles (time picker; end must be after start), Once/Daily/Weekly segmented picker with the rule spelled out, lesson plan (class only), colour swatches. Replaced the old `ScheduleEntryFormDialog` and the separate day screen. |
| **PersonInviteDialog** | `shared/widgets/person_invite_dialog.dart` | Manage Teachers/Children | Shared name/email/phone dialog for teacher & parent invites. |
| **ClassFormDialog** | `shared/widgets/class_form_dialog.dart` | ManageClassesScreen | Create/edit-a-class dialog: name + teacher dropdown. |
| **EditableField** | `shared/widgets/editable_field.dart` | Child/Class/Person detail | One field that cross-fades between a read-only row (optionally tap-to-copy) and a text input, driven by an `editing` flag. |
| **AvatarWithPreview** | `shared/widgets/avatar_preview.dart` | Detail screens | Round avatar that opens a full-screen pinch-zoom photo preview when tapped. |
| **SignedPhotoThumbnail** | `shared/widgets/signed_photo_thumbnail.dart` | Attendance screens | Round thumbnail from a private Storage path (attendance-photos), via signed URL. |
| **SignedAvatar** | `shared/widgets/signed_avatar.dart` | Profile / detail screens | Round avatar from any bucket's signed-URL provider, with a placeholder. |
| **AvatarSourceSheet** | `shared/widgets/avatar_source_sheet.dart` | Avatar edits | The take-photo / choose-from-gallery bottom sheet. |
| **AttendanceStatusChip** | `shared/widgets/attendance_status_chip.dart` | Attendance screens | Dot pill per status, plus `AttendanceStatusStyle` (shared colours/labels/icons), `AttendanceStatusBadge` (round tile badge) and `formatClock` (local HH:mm). |
| **LessonPlanStatusChip** | `shared/widgets/lesson_plan_status_chip.dart` | Lesson plan screens | Colored Draft/Awaiting approval/Approved/Rejected chip. |
| **LogoutButton** | `shared/widgets/logout_button.dart` | *(currently unused — sign-out lives in the Profile tab)* | Confirm-then-sign-out icon button. |

---

## Naming cheatsheet

When we talk, these are the short names to use:

- **"the teacher attendance screen"** = MarkAttendanceScreen
- **"the director attendance screen"** = DirectorAttendanceScreen
- **"the child detail screen"** = ChildDetailScreen
- **"the person/profile detail screen"** = PersonDetailScreen
- **"the People tab"** = PeopleScreen (Teachers/Children/Classes sub-tabs)
- **"the manage classes screen"** = ManageClassesScreen (People › Classes)
- **"the profile tab"** = ProfileScreen
- **"the set-password screen"** = SetPasswordScreen (invite + recovery)
