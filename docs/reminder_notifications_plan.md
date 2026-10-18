# Technical Plan: Study Reminder Notifications (flutter_local_notifications)

**Goal:** local, scheduled reminders that nudge the learner to study — at three scopes:
**everything** (global), **a specific course**, or **a specific theme** — using
[`flutter_local_notifications`](https://pub.dev/packages/flutter_local_notifications).

**Status:** plan only. No implementation done yet.

---

## 1. Recommended Architecture (read this first)

The system is a small, deterministic loop with three parts:

1. **Persisted subscriptions** (drift) describe *what* the user wants: scope, target, time of day.
2. **A pure domain scheduler** computes concrete fire times and notification IDs from those subscriptions.
3. **A thin platform gateway** around `flutter_local_notifications` turns those into real scheduled notifications.

**Canonical rescheduling rule:** the database is the single source of truth. On every relevant change
(subscription edited, course/theme deleted, app start), we **cancel everything and re-schedule from the DB**.
We never try to "track" what the OS currently has scheduled — `pendingNotificationRequests()` is used only
for verification/debug. This makes reboots, time-zone changes, and deletions trivially correct.

| Layer | File (planned) | Responsibility |
|---|---|---|
| Domain | `lib/domain/reminders/reminder.dart` | `ReminderSubscription` entity, `ReminderScope { global, course, theme }` |
| Domain | `lib/domain/reminders/reminder_scheduler.dart` | Pure functions: ID scheme, next fire time, schedule plan |
| Domain | `lib/domain/reminders/notification_gateway.dart` | Abstract gateway interface (keeps domain plugin-free + testable) |
| Data | migration on `app_database` + `ReminderSubscriptions` table | Persistence |
| Data | `lib/data/repositories/drift_reminder_repository.dart` | CRUD for subscriptions |
| Data | `lib/data/notifications/local_notification_gateway.dart` | `flutter_local_notifications` implementation |
| Presentation | `lib/presentation/screens/reminder_settings_screen.dart` + providers | UI |

---

## 2. Scope Model

| Scope | Target | Suggested copy (body) |
|---|---|---|
| Global | — | "Time to review your flashcards" |
| Course | `courseId` | "Time to review: *<course name>*" |
| Theme | `themeId` | "Time to review: *<theme name>*" |

A subscription is: `{ scope, targetId?, hour, minute, daysOfWeek?, enabled }`.

**Constraint — one subscription per (scope, target):** at most one reminder per target
(one global, one per course, one per theme). Enforced in the repository (upsert keyed on
`(scope, targetId)`) and in the UI (a target with a reminder shows "edit", not "add").
Rationale: the notification ID scheme in section 4 assigns one weekday slot per target —
a second subscription on the same target would collide on IDs and silently overwrite the
first (`zonedSchedule` with the same id replaces).

> **Decision D1 — due-card counts in the body:** scheduled notifications fire when the app is NOT
> running, so we cannot compute live due counts at fire time.
> - **Option A (recommended for v1):** static copy. Simple, always correct.
> - **Option B (v1+):** refresh scheduled bodies with current due counts whenever the app opens or a
>   review session ends. Nicer UX, adds a rescheduling hook and ordering complexity (last write wins).

---

## 3. flutter_local_notifications — research findings

### 3.1 Scheduling API

`zonedSchedule` requires a `TZDateTime` from the `timezone` package (fixes DST bugs of the old
`schedule`). Recurrence via `matchDateTimeComponents`:

| Want | `matchDateTimeComponents` |
|---|---|
| Every day at H:mm | `DateTimeComponents.time` |
| Weekly on a weekday at H:mm | `DateTimeComponents.dayOfWeekAndTime` |

Supporting `daysOfWeek` therefore means scheduling **one recurring notification per selected weekday**
per subscription (max 7) — a known, bounded cost.

### 3.2 Platform setup cost (one-time)

**Android (AndroidManifest.xml):**
```xml
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<!-- Only if exact alarms are chosen (see D2): -->
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
```
Plus a drawable for the small icon, e.g.
`AndroidInitializationSettings('app_icon')` — we must ship an `app_icon` drawable resource.

**Notification channel (Android 8+):** `AndroidNotificationDetails(channelId, channelName)`
requires a stable, pre-decided channel. One channel: id `study_reminders`, name
"Study reminders" — the name is user-visible in system settings. Channel importance can't
be raised later without a new channel id, so pick it up front (`IMPORTANCE_DEFAULT`).
Users can disable the channel in OS settings; T5 adds detection plus an OS-settings
deep-link for recovery.

**Android 13+:** notifications are a runtime permission —
`AndroidFlutterLocalNotificationsPlugin().requestNotificationsPermission()`, called when the user
enables their first reminder.

**iOS:** request authorization via `DarwinInitializationSettings(requestAlertPermission...)`
or resolve the iOS implementation and request explicitly. Same trigger: first enabling a reminder.
Decide the permission set up front — alert + sound, **no badge** — because adding a
permission later means re-prompting the user.

**Timezone:** `tz.initializeTimeZones()` + set the local location from the device zone
(`flutter_timezone` package; the timezone package cannot detect it alone).

### 3.3 Precision — exact vs. inexact

`androidScheduleMode` decides delivery precision:

> **Decision D2 — delivery precision:**
> - **`AndroidScheduleMode.inexactAllowWhileIdle` (recommended):** daily study reminders tolerate a few
>   minutes of jitter. No `SCHEDULE_EXACT_ALARM` permission, no Play-store exact-alarm audit class.
> - **`exactAllowWhileIdle`:** minute-accurate, but needs the permission, and if the user revokes it the
>   plugin logs an error and **recurring notifications silently stop being scheduled** — an ugly failure
>   mode for a reminder feature.

### 3.4 Tap handling

Two paths, both required:
- App running/background: `onDidReceiveNotificationResponse` → read `payload`.
- Cold start: `getNotificationAppLaunchDetails()` at app launch → read same payload.

Payload is a small JSON: `{"scope":"course","courseId":5}`. A registered handler routes to the
existing `StudySessionLauncher` for that scope via a root `NavigatorKey` — a **new prerequisite**:
today's `MaterialApp` (lib/main.dart) has no navigator key, and its home is an
onboarding-gated `settings.when(...)` builder. The handler must defer routing until the
gate resolves (post-first-frame) or a cold-start tap can hit an unbuilt navigator and drop.

### 3.5 Life-cycle & cancellation

- `zonedSchedule(..., id)` with the **same id replaces** the previous notification — updates are
  "schedule with same id".
- `cancel(id)` / `cancelAll()`; `pendingNotificationRequests()` for debug verification.
- **Device reboot:** the plugin reschedules automatically thanks to `RECEIVE_BOOT_COMPLETED`.
  Our reconcile-on-app-start is still kept as backstop.

---

## 4. Notification ID Scheme

Android/iOS IDs are 32-bit ints. Deterministic, decoded without a lookup table.
One slot per weekday per target — this is why section 2 caps subscriptions at one per
(scope, target):

| Range | Owner | Layout |
|---|---|---|
| 0–6 | Global | `dayIdx` (0 = Mon) if weekly reminder; 0 if daily |
| 1_000_000 + courseId×10 + dayIdx | Course | one slot per weekday |
| 1_000_000_000 + themeId×10 + dayIdx | Theme | one slot per weekday |

Full int32 range 0…2,147,483,647 comfortably holds `1_000_000_000 + themeId×10 + 6` for any
realistic theme id. The scheme is a pure, unit-tested function: `notificationId(scope, targetId, dayIdx)`.

---

## 5. Open Product Decisions (recommendations in bold)

| # | Question | Recommendation |
|---|---|---|
| D1 | Static copy vs. due counts in body | **Static for v1**, Option B later |
| D2 | Exact vs. inexact delivery | **Inexact** — no permission burden, right precision for reminders |
| D3 | Recurrence granularity | **Daily at HH:mm for v1**; weekday selection is a small extension (already designed for) |
| D4 | Where do users configure per-course/theme reminders? | **Settings screen "Reminders" section** listing all subscriptions + "add reminder"; toggle per course/theme rows |
| D5 | Reminder time default | **18:00 local**, user-editable |
| D6 | Include subscriptions in backup/restore? | **Yes** — export alongside other settings. On restore, reconcile-on-app-start rebuilds scheduling from the restored DB, so nothing is trusted from the export. Excluding them would silently lose user configuration on device migration |

---

## 6. Implementation Phases (ODD tasks, test-first where runnable)

| # | Task | Deliverable | Verification |
|---|---|---|---|
| T1 | Dependencies + platform config | `flutter_local_notifications`, `timezone`, `flutter_timezone` in pubspec; manifest changes; app_icon drawable; `study_reminders` channel constants; init wiring in `main.dart` | App builds; init runs without error |
| T2 | Reminder persistence | `ReminderSubscriptions` drift table + migration + DAO + repository | DAO tests (drift), migration test |
| T3 | Domain scheduler (pure) | Entity, ID scheme, next-fire-time computation (`ReminderScope`, `notificationId`, `nextFireTime`) | Unit tests: daily/weekly cases, DST-safe next occurrence, ID round-trip |
| T4 | Gateway + reconciliation | `LocalNotificationGateway`, `syncReminders()` = cancelAll + reschedule from DB; called on app start and on every subscription change | Unit tests with fake plugin; manual device check `pendingNotificationRequests()` |
| T5 | Permission flow | Request OS permission on first "enable"; graceful state when denied (UI note + still-save subscription as disabled); detect OS-disabled `study_reminders` channel and offer a deep-link to app notification settings for recovery | Manual: Android 13+ & iOS flows |
| T6 | Settings UI | Reminders section: add/edit/delete subscription, time picker, scope picker (course/theme names from repo) | Widget tests + manual |
| T7 | Payload → study route | Attach root `navigatorKey` to `MaterialApp`; handler + `getNotificationAppLaunchDetails()` on cold start, deferred until the onboarding gate resolves; route into study session for payload scope | Manual: tap in foreground, background, cold start |

Suggested single feature branch with per-phase work-unit commits.

---

## 7. Edge Cases & Risks

- **Deleted course/theme** → its subscriptions must cascade-delete (FK in drift) so nothing schedules ghosts.
- **Archived course** → skip (or keep but flag in UI); decide with D4 UI design. Default: archived courses' reminders stay but are visually marked.
- **Time-zone change → reconcile** on next app start; scheduled `TZDateTime`s stay correct because they are zone-aware.
- **Exact-alarm revocation (only if D2 exact chosen):** recurring notifications stop; avoid by recommending inexact.
- **iOS 64 pending-notification cap:** unreachable (max 7 per subscription × few subscriptions).
- **Reminder fires while user studies:** harmless; tapping starts a fresh session per current launcher behavior.
- **User disables the `study_reminders` channel in OS settings:** Android accepts the schedule but shows nothing. T5's detection + settings deep-link recovers; no in-app workaround exists.
- **Backup/restore (D6):** subscriptions are exported with settings; after restore, reconcile-on-app-start rebuilds all scheduling from the restored DB — no stale OS state can survive.

---

## 8. Next Step

Confirm D1–D6 (each has a bolded recommendation), then start with **T1+D3** as the first work unit.
