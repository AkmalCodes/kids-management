# KawanKecil

**Childcare centre management app for directors, teachers and parents — one app, three experiences.**

KawanKecil replaces the WhatsApp groups, paper attendance sheets and spreadsheets a small childcare centre runs on.
Directors manage people and classes, teachers handle the day (attendance, lessons, daily reports), and parents see
exactly what their child did today.

> Status: **in active development (~65%)**. Core role flows work end to end; marketing site and subscriptions are next.

![KawanKecil hero banner](docs/readme/hero.png)
<!-- PLACEHOLDER: wide banner — app logo + 3 phone mockups (director / teacher / parent) -->

---

## Features

### For directors
- **People** — manage teachers, children and classes; enrol a child and assign a class.
- **Schedules** — see and edit every teacher's and class's schedule, with recurring events.
- **Lessons** — view all lesson plans and subjects across the centre.
- **Attendance** — children's attendance and staff clock-in/out for any day.
- **Invites** — add a parent or teacher; they get an email to set their own password.

### For teachers
- **Clock in / out** with a weekly view of their own days.
- **Attendance** — mark children present/absent from a class grid.
- **Lesson plans** — create and edit plans, linked to schedule events, with co-teacher support.
- **Daily reports** — text and photos for each child, sent to the parent.
- **Schedule** — manage their own schedule, view (not edit) colleagues'.

### For parents
- **Today first** — the child's attendance, schedule and today's report on one screen.
- **Reports** — daily reports with photos.
- **Schedule & attendance history** for their own child only.

---

## Screenshots

| Role | Screen | Preview |
|---|---|---|
| All | Login | ![Login](docs/readme/login.png) <!-- PLACEHOLDER --> |
| All | Set password (web, from invite email) | ![Set password](docs/readme/set-password.png) <!-- PLACEHOLDER --> |
| Director | People — Teachers / Children / Classes | ![Director people](docs/readme/director-people.png) <!-- PLACEHOLDER --> |
| Director | Schedule | ![Director schedule](docs/readme/director-schedule.png) <!-- PLACEHOLDER --> |
| Director | Attendance (children + teachers for a day) | ![Director attendance](docs/readme/director-attendance.png) <!-- PLACEHOLDER --> |
| Teacher | Clock in / out | ![Teacher clock in](docs/readme/teacher-clock.png) <!-- PLACEHOLDER --> |
| Teacher | Attendance grid | ![Teacher attendance](docs/readme/teacher-attendance.png) <!-- PLACEHOLDER --> |
| Teacher | Lesson plan | ![Teacher lessons](docs/readme/teacher-lessons.png) <!-- PLACEHOLDER --> |
| Teacher | Daily report | ![Teacher report](docs/readme/teacher-report.png) <!-- PLACEHOLDER --> |
| Parent | Today (attendance + report) | ![Parent today](docs/readme/parent-today.png) <!-- PLACEHOLDER --> |
| Parent | Reports | ![Parent reports](docs/readme/parent-reports.png) <!-- PLACEHOLDER --> |

<!-- Put the PNGs in docs/readme/ with the file names above. A short GIF of one teacher flow
     (clock in -> attendance -> daily report) is worth adding as docs/readme/demo.gif. -->

---

## Pricing (planned)

| Phase | Who | Price |
|---|---|---|
| **Early access** (now → full release) | Centres that join before launch | **Free**, in exchange for regular feedback |
| **Founding centres** | Every centre that joined during early access | **Founding price for life** — `RM __ / month` <!-- PLACEHOLDER --> (lower than standard, kept while the subscription stays active) |
| **Standard** | Centres joining after full release | `RM __ / month` <!-- PLACEHOLDER --> for the current feature set |

<!-- Decide: price per centre or per child; branch limit; whether a free tier exists after launch. -->

Interested in early access? → **[Landing page link]** <!-- PLACEHOLDER: marketing site URL -->

---

## Tech stack

| Layer | Technology |
|---|---|
| App | Flutter (Dart) — Android, iOS and web from one codebase |
| State | Riverpod |
| Backend | Supabase — PostgreSQL, Auth, Storage, Edge Functions |
| Security | Role-based access enforced by **Row Level Security** in the database, not just the UI |
| Email | Invite and password-recovery emails through a custom sending domain (Mailgun) |
| Web | Static set-password page at `kids.akmalcodes.quest` for links in invite/recovery emails |

Architecture notes and the full design spec: [docs/superpowers/specs/](docs/superpowers/specs/)
(start with `2026-07-01-childcare-management-design.md` and `screen-map.md`).

---

## Running the app

Supabase credentials are passed via `--dart-define`, never hardcoded (see [lib/main.dart](lib/main.dart)):

```bash
flutter run --dart-define=SUPABASE_URL=https://rpefksoutqsbreiyppee.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwZWZrc291dHFzYnJlaXlwcGVlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM2NTczNTksImV4cCI6MjA5OTIzMzM1OX0.5JaEhJGwO75hIoBOb7wM2hpPDmsr1AenTM8-tCgtIRM
```

> The anon key is safe to commit — it's designed to be public and is protected by the Row Level Security policies in
> the database, not by secrecy. The `service_role` key (not used in this app) is the one that must never be shared.

## Running tests

```bash
flutter test
```

---

## Roadmap

- [x] Role-based login and routing (director / teacher / parent)
- [x] People, classes and enrolment
- [x] Schedules with recurrence and co-teachers
- [x] Children's attendance and staff clock-in/out
- [x] Lesson plans and daily reports with photos
- [x] Invite / set-password flow by email
- [ ] Landing page with pricing and early-access sign-up
- [ ] Subscriptions (early access → founding price → standard)
- [ ] Push notifications
- [ ] Play Store / App Store release

## Author

Built by **Akmal Hisyam** — [GitHub @AkmalCodes](https://github.com/AkmalCodes)
