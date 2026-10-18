# Feature: Study Reminder Notifications

Objective: local, scheduled study reminders (global / per course / per theme) via `flutter_local_notifications`, per `docs/reminder_notifications_plan.md`.
Branch: `feature/reminder-notifications` · Delivery: single feature branch, per-phase work-unit commits (plan §6), one PR at the end.
Test runner: `flutter test --exclude-tags integration` (CI parity) · Analyze: `flutter analyze` (very_good_analysis).

## Specs

Source of truth: `docs/reminder_notifications_plan.md` (confirmed by user with its bolded D1–D6 recommendations).

- S1 (plan §1): "the database is the single source of truth. On every relevant change (subscription edited, course/theme deleted, app start), we **cancel everything and re-schedule from the DB**."
- S2 (plan §2): "A subscription is: `{ scope, targetId?, hour, minute, daysOfWeek?, enabled }`." plus the added constraint: "**Constraint — one subscription per (scope, target):** at most one reminder per target... Enforced in the repository (upsert keyed on `(scope, targetId)`) and in the UI".
- S3 (D1): "**Static for v1**" — no due-card counts in notification bodies.
- S4 (D2): "**`AndroidScheduleMode.inexactAllowWhileIdle`** (recommended)... No `SCHEDULE_EXACT_ALARM` permission" — manifest must NOT declare `SCHEDULE_EXACT_ALARM`.
- S5 (D3 + §3.1): "**Daily at HH:mm for v1**; weekday selection is a small extension (already designed for)"; "scheduling **one recurring notification per selected weekday** per subscription (max 7)".
- S6 (D4): "**Settings screen 'Reminders' section** listing all subscriptions + "add reminder"; toggle per course/theme rows".
- S7 (D5): "**18:00 local**, user-editable".
- S8 (D6): "**Yes** — export alongside other settings. On restore, reconcile-on-app-start rebuilds scheduling from the restored DB, so nothing is trusted from the export."
- S9 (§3.2): "One channel: id `study_reminders`, name 'Study reminders'" — user-visible; `IMPORTANCE_DEFAULT`; manifest needs `RECEIVE_BOOT_COMPLETED` + `POST_NOTIFICATIONS`; `app_icon` drawable must exist.
- S10 (§3.2 + T5): "`AndroidFlutterLocalNotificationsPlugin().requestNotificationsPermission()`, called when the user enables their first reminder." Denied → "graceful state when denied (UI note + still-save subscription as disabled); detect OS-disabled `study_reminders` channel and offer a deep-link to app notification settings for recovery".
- S11 (§3.4 + T7): "Payload is a small JSON: `{"scope":"course","courseId":5}`" → route via `startStudySession` / `startGlobalStudySession` "via a root `NavigatorKey`"; "The handler must defer routing until the gate resolves (post-first-frame)".
- S12 (§4): ID ranges "0–6 | Global", "1_000_000 + courseId×10 + dayIdx | Course", "1_000_000_000 + themeId×10 + dayIdx | Theme"; "`notificationId(scope, targetId, dayIdx)`" is a pure unit-tested function; dayIdx 0 = Mon.
- S13 (§7): "a deleted course/theme... its subscriptions must cascade-delete (FK in drift) so nothing schedules ghosts."
- S14 (explorer finding, plan correction): the repo has **no `ios/` directory** — the app targets Android only. Every iOS item in the plan (Darwin authorization, badge/sound, 64-notification cap) is N/A for this codebase.

## Tasks

| # | Task | S# | Route | Status | Commit/evidence |
|---|------|----|-------|--------|-----------------|
| T1 | Dependencies + platform config (pubspec, manifest, app_icon drawable, timezone init wiring in main.dart) | S4, S9, S14 | inline | ✅ done | aed516c · RED: 5 failures (perms/drawable/init function) → GREEN: 340 pass, analyze clean (2 lint infos fixed, amended) |
| T2 | Reminder persistence: `ReminderSubscriptions` table (schema v4), migration + snapshots, DAO, drift repository, providers | S2, S13 | delegated (parallel w/ T3) | ✅ done | ef1f400 (+985477c verifier probes) · RED→GREEN 13 tests, schema chain v1→v4, independent verifier PASS (scratch-verified snapshots additive, CHECK/UNIQUE/cascade enforced) |
| T3 | Domain scheduler (pure): `notificationId`, `nextFireTime`, schedule plan; unit tests | S3, S5, S11, S12 | delegated (parallel w/ T2) | ✅ done | 6f6d851 · RED→GREEN 44 tests incl. DST spring-forward; seam check 397 green |
| T4 | Gateway + reconciliation: `LocalNotificationGateway`, `syncReminders()` = cancelAll + reschedule; called on app start and on subscription change | S1, S4, S5, S9, S12 | inline | pending | |
| T5 | Permission flow: request on first enable, denied state, channel-disable detection + settings deep-link | S10 | inline | pending | |
| T6 | Settings UI: Reminders section, add/edit/delete, time picker, scope picker | S2, S6, S7 | inline (re-route if context demands) | pending | |
| T7 | Payload → study route: root navigatorKey, cold-start launch details, onboarding-gate-safe deferred routing | S11 | inline | pending | |

## Log

- L1 (2026-10-18, user): "New execute the plan" — authorizes implementation of `docs/reminder_notifications_plan.md` (authored 2026-10-18 and updated in the same session) with its bolded D1–D6 recommendations treated as confirmed.
- L2 (2026-10-18, explorer): repo has no `ios/` directory (Android-only) — plan iOS items inapplicable (S14). `lib/main.dart` has no `WidgetsFlutterBinding.ensureInitialized()`, no navigatorKey, home is onboarding-gated `settings.when(...)`. Drift schema v3; migrations are guarded `if (from < N)` blocks; schema snapshots in `drift_schemas/`, suite in `test/data/schema_test.dart`; regenerate with `dart run drift_dev schema generate --data-classes drift_schemas/ test/generated_migrations/`. Providers are code-gen in `lib/presentation/providers.dart` (riverpod_generator). Backup is repo-based exporter/importer with field-pinned settings; adding reminders to export = new top-level JSON key (S8) — done in the T6-adjacent backup step (see T8 below if split).
- L3 (2026-10-18): delivery strategy fixed from plan §6 "Suggested single feature branch with per-phase work-unit commits" — no chain-strategy question needed. Forecast exceeds 400 authored lines; `single-pr` covers it.
- L4 (2026-10-18): domain seams (entity, repository interface, gateway interface, ID/scoping constants) created inline by parent BEFORE delegating T2/T3, so both parallel writers build against stable contracts without seeing each other's files.
- L5 (2026-10-18, T1 evidence): `flutter pub add` changed 9 deps cleanly. Manifest test initially caught its own comment containing the forbidden token — reworded the comment, the test now pins the absence for real. Android-only confirmed: no iOS code written.
- L6 (2026-10-18, T2/T3): parallel writers T2+T3 delivered against frozen seams; surfaces disjoint, spot check + seam suite green (397). Domain seams committed separately first (ff6f251).
- L7 (2026-10-18, verification): T2 names Risk item 1 (schema v4 migration). Independent verifier PASS, 0 blockers. Advisories logged: (a) DB-level allows duplicate global rows (unique+NULLs); repository is the only guard — T8 backup import MUST write through DriftReminderRepository.upsert, never raw inserts; (b) upsert find-then-replace outside transaction — unreachable in single-isolate app.
- L8 (2026-10-18, native RDD): assess ff6f251..HEAD → high_risk/review_due (escalation item 1). User GRANTED consent, but START failed preflight: `lens_context_budget_exceeded` — 8,858-line slice (generated drift snapshots + codegen) exceeds the reviewer context budget. No authority created (not_started). Per stop table: terminal for this candidate. Process correction: assess IMMEDIATELY after each remaining work-unit commit so future slices stay reviewable small. Reviewed boundary stays at ff6f251 (nothing was acknowledged); next slices assess from base-ref ff6f251.
- T8 added (S8 backup export/import for reminder subscriptions) — separated from T2 because it touches a different subsystem; route inline, after T4.
