# KawanKecil

Flutter app for managing children's schedules, teacher schedules, and attendance. See [docs/superpowers/specs/2026-07-01-childcare-management-design.md](docs/superpowers/specs/2026-07-01-childcare-management-design.md) for the full design spec.

## Running the app

Supabase credentials are passed via `--dart-define`, never hardcoded (see [lib/main.dart](lib/main.dart)):

```bash
flutter run --dart-define=SUPABASE_URL=https://rpefksoutqsbreiyppee.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwZWZrc291dHFzYnJlaXlwcGVlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM2NTczNTksImV4cCI6MjA5OTIzMzM1OX0.5JaEhJGwO75hIoBOb7wM2hpPDmsr1AenTM8-tCgtIRM
```

> The anon key is safe to commit — it's designed to be public and is protected by the Row Level Security policies in the database, not by secrecy. The `service_role` key (not used in this app) is the one that must never be shared.

## Running tests

```bash
flutter test
```
