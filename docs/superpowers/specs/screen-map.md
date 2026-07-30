# Screen Map — Childcare Manager

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
| Attendance | **MarkAttendanceScreen** | `features/teacher/screens/mark_attendance_screen.dart` | Today's class as a searchable list of **collapsible cards** (avatar, name, status chip, chevron). Expand to mark Present/Absent and optionally attach a check-in and/or belongings photo (take/gallery/delete). Shows today's date in the header. |
| Lessons | — | *(placeholder, not built)* | |
| Reports | **TeacherReportsScreen** | `features/teacher/screens/teacher_reports_screen.dart` | The teacher's class as a list; tap a child → DailyReportEditScreen. |
| (from a child row) | **DailyReportEditScreen** | `features/teacher/screens/daily_report_edit_screen.dart` | Write/edit today's daily report for one child: free text + photos (add/remove). Opens the existing report or a blank form. |
| Profile | **ProfileScreen** | see *Profile* below | |

---

## Director tab screens

| Tab | Name | File | What's on it |
|---|---|---|---|
| People | **PeopleScreen** | `features/director/screens/people_screen.dart` | Wrapper with **Teachers \| Children \| Classes** sub-tabs. |
| People › Teachers | **ManageTeachersScreen** | `features/director/screens/manage_teachers_screen.dart` | Teacher list; **+** invites a teacher; tap a row → PersonDetailScreen. |
| People › Children | **ManageChildrenScreen** | `features/director/screens/manage_children_screen.dart` | Child list; **+** opens EnrollChildScreen; per-row icon invites a parent; tap a row → ChildDetailScreen. |
| People › Classes | **ManageClassesScreen** | `features/director/screens/manage_classes_screen.dart` | Class list (with assigned teacher); **+** creates a class; tap a row → edit dialog (rename / reassign teacher). |
| (from Children +) | **EnrollChildScreen** | `features/director/screens/enroll_child_screen.dart` | Create a child record + invite its first parent in one form. |
| (from a child row) | **ChildDetailScreen** | `features/director/screens/child_detail_screen.dart` | Director view/edit of one child: photo, name, DOB (age shown), **class** (dropdown → class_id, drives the parent schedule), class teacher, allergies, notes + a read-only **Parents** section (name + email). |
| (from a teacher row / Profile) | **PersonDetailScreen** | `features/profile/person_detail_screen.dart` | View/edit a person's photo, name, phone. Reused for self-edit from the Profile tab and director-edits-other from People. |
| Schedule | **DirectorSchedulesScreen** | `features/director/screens/director_schedules_screen.dart` | Searchable **class** list → PersonScheduleScreen for that class. |
| (from a class) | **PersonScheduleScreen** | `features/director/screens/person_schedule_screen.dart` | Reusable editable agenda view (type='class'/'teacher'/'child'). |
| Lessons | — | *(placeholder, not built)* | |
| Attendance | **DirectorAttendanceScreen** | `features/director/screens/director_attendance_screen.dart` | All children for a chosen date as **collapsible cards** (same style as the teacher screen, read-only); expand to see the day's photos. Date picker in the header. |
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
| **DayScheduleScreen** | `shared/screens/day_schedule_screen.dart` | Schedule flows | Hourly view for a single day; owns create/edit/delete of schedule entries. |
| **ScheduleAgendaView** | `shared/widgets/schedule_agenda_view.dart` | Schedule screens | Week/month toggle with colored event cards; tap a day to drill in. |
| **DayTimetable** | `shared/widgets/day_timetable.dart` | DayScheduleScreen | The hour grid; tap-to-add/edit, fade-in on new entries. |
| **ScheduleEntryFormDialog** | `shared/widgets/schedule_entry_form_dialog.dart` | Schedule create/edit | Dialog for an event's label, times, and color. |
| **PersonInviteDialog** | `shared/widgets/person_invite_dialog.dart` | Manage Teachers/Children | Shared name/email/phone dialog for teacher & parent invites. |
| **ClassFormDialog** | `shared/widgets/class_form_dialog.dart` | ManageClassesScreen | Create/edit-a-class dialog: name + teacher dropdown. |
| **SignedPhotoThumbnail** | `shared/widgets/signed_photo_thumbnail.dart` | Attendance screens | Round thumbnail from a private Storage path (attendance-photos), via signed URL. |
| **SignedAvatar** | `shared/widgets/signed_avatar.dart` | Profile / detail screens | Round avatar from any bucket's signed-URL provider, with a placeholder. |
| **AvatarSourceSheet** | `shared/widgets/avatar_source_sheet.dart` | Avatar edits | The take-photo / choose-from-gallery bottom sheet. |
| **AttendanceStatusChip** | `shared/widgets/attendance_status_chip.dart` | Attendance screens | Colored Present/Absent/Late/Excused chip. |
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
