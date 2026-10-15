# Plan: Build Order and Task Checklist

Companion to [`design.md`](design.md) — that file says *what* to build and *why*; this file
says *in what order* and *how each task is verified*.

Forecast: **~4,200 authored changed lines** (additions + deletions, generated files excluded).
That is the planning heuristic only — not a cap, and not a reason to delete comments or split
work artificially.

## Quick path

1. Complete List 1 (foundation) and List 2 (persistence).
2. Complete List 3 (scheduler) — stops here until reference vectors pass.
3. Lists 5 → 6 give a usable app with no AI involved.
4. Lists 4 → 7 → 8 add onboarding, theming, then the AI pipeline.
5. List 9 gates run alongside every list, not at the end.

**Build order:** L1 → L2 → L3 → L5 → L6 → L7 → L4 → L8 → L9 → L10.

> Correction to my earlier reply: authoring (L5) must precede review (L6), because the
> review engine needs cards to exist. The earlier order put L6 before L5, which was wrong.

**Why L8 is last:** the AI pipeline is the only feature that can fail for reasons outside
the app (network, provider, model behavior). Building it last means the app is already
useful and testable before that risk lands.

## Delivery strategy

**Local-only. No PRs.** No git remote is configured, and that is the accepted decision
(T0.2), not a missing step — so no PR mechanism exists and `single-pr`, `chained-pr`, and
`work-unit-commits` are all inapplicable for now.

Consequence, recorded honestly:

- Work proceeds as **local work-unit commits** on the feature branch, one per list or per
  coherent sub-list.
- The `docs/app-plan` branch already exists and holds this plan.
- **Deferred:** if a remote is added later, the ~4,200-line forecast exceeds the ~400-line
  review budget, so a chain strategy (`stacked-to-main` or `feature-branch-chain`) becomes
  required. Resolve the `chained-pr` skill then. Not addressed now.

Feature-document mirror: `odd/local-first-flashcards/tasks` in Engram, plus this file.

---

## List 0 — Bootstrap

- [x] **T0.1** Branch for the plan (`docs/app-plan`). *Done: branch exists, plan committed.*
- [x] **T0.2** **Resolved: no git remote. Stay local-only.** Delivery proceeds as local
  work-unit commits on a feature branch. No pull requests until a remote is added.
  *Verification: `git remote -v` is empty by decision, not by oversight.*

## List 1 — Foundation

- [x] **T1.1** Create the project **Android only**:
  `flutter create --platforms=android --org dev.flashcards2 --project-name flashcards2 .`
  Do not scaffold iOS, web, or desktop.
  *Done. `android/` present; `ios/ web/ linux/ windows/ macos/` absent. `applicationId` =
  `dev.flashcards2.flashcards2` (matches the `dev.<name>.<name>` convention from the
  sibling `neuronutri` project). Note: `flutter create` also ran `pub get` automatically.*
- [x] **T1.1a** **Merge Flutter's `.gitignore` patterns into the existing root
  `.gitignore`.**
  `flutter create` **preserves an existing `.gitignore` verbatim** and silently writes
  none of its own patterns. Confirmed on this repo: after `flutter create`, the root
  `.gitignore` was still 3 lines while `.dart_tool/` already existed and 5 artifact paths
  were stageable.
  *Done. Gate verified under a real build: `flutter build apk --debug` succeeded, `build/`
  and `.dart_tool/` both exist, and neither is stageable. 27 source files track; 0 artifacts.*
- [x] **T1.2** Add dependencies.
  *Done, with two corrections against the original plan:*
  - **`sqflite` dropped in favour of `drift_flutter` + `path_provider`.** Drift's current
    setup guide uses `drift_flutter`; `sqflite` is not the recommended path.
    `sqlite3_flutter_libs` is now **EOL** and is pulled in transitively as a shim — it must
    not be added explicitly.
  - **`riverpod_lint` + `custom_lint` are mutually exclusive** in this dependency graph
    (analyzer / `_macros` conflict through `drift_dev`). `pub add` failed atomically;
    both were dropped. Riverpod still works without its linter.
  - `sqlite3` resolves to 3.5.2 rather than 3.7.1 because `objective_c` pins `hooks`
    below what 3.7.1 needs. Benign, and `pub upgrade sqlite3` confirms it cannot move.
- [x] **T1.3** `very_good_analysis` + strict `analysis_options.yaml`.
  *Done at full strength (yellow-flag standard, as requested). 3 real findings found by
  `dart fix`/`flutter analyze` were **fixed in code, not suppressed**. One narrow, reasoned
  exception: `public_member_api_docs: false`. Generated files excluded.
  Note: `flutter pub remove flutter_lints` rewrites `analysis_options.yaml`, adding
  `build/**` and `android/**` excludes — verify the file after any `pub remove`.*
- [x] **T1.4** Folder skeleton `data/ domain/ presentation/ core/`.
  *Done. Note the template `lib/main.dart` counter demo was replaced with a real app shell
  (Riverpod `ProviderScope`, Material 3 light/dark) plus `test/app_test.dart`, because
  deleting it left `flutter test` failing.*
- [x] **T1.5** CI: `flutter analyze` + `flutter test` on push.
  *Done: `.github/workflows/ci.yml`. Cannot run until a remote exists (T0.2), so it is
  committed-but-unexercised. Local equivalents verified green. Flutter is pinned to an
  exact version in the workflow (see T1.6).*
- [x] **T1.6** Pin the Flutter version for reproducibility.
  *Resolved: **CI is the authoritative pin.***
  `puro use stable` writes `.puro.json`, but it also adds that file to
  `.git/info/exclude`, which is local-only and never committed — so a repo-level pin is not
  possible without fighting puro. Instead, `.github/workflows/ci.yml` declares an exact
  `flutter-version: 3.47.7`, so CI cannot drift when the `stable` channel advances.
  The local environment also runs 3.47.7, so CI and local currently agree.
  *Maintenance: when the local Flutter is upgraded, update `flutter-version` in the
  workflow in the same change. Divergence is otherwise silent.*

## List 2 — Persistence

- [x] **T2.1** Drift tables: `courses`, `themes`, `cards`, `card_images`,
  `schedule_states`, `review_logs`, `app_settings`.
  *Done. All seven tables exist with cascade FKs, `PRAGMA foreign_keys = ON`, and
  `textEnum` columns. `card_images` stores filesystem paths — verified no BLOB column
  exists anywhere. **No FSRS math** leaked into the data layer (grep-checked; the only
  matches are comments documenting the boundary).*
  Two real API conflicts found and resolved:
  - **`new` is a reserved Dart keyword**, so no enum member can be named `new` and Drift's
    `textEnum` cannot express `ReviewState`. Confirmed independently (`expected_identifier_but_got_keyword`).
    Resolved with a hand-written `ReviewStateConverter`; a raw-SQL test asserts the stored
    value is literally `new`, so the Dart-side `new_` workaround never reaches the database.
  - **Name collisions with Drift's runtime API**: the `AppSettings` table class clashed with
    the domain entity, and DAO methods named `update`/`delete` clashed with
    `DatabaseConnectionUser.update`/`delete`. Resolved via `@DataClassName` suffixes and
    domain-specific DAO method names.
- [x] **T2.2** Migration v1 + schema export test.
  *Done. `schemaVersion = 1` with an explicit `MigrationStrategy`. Snapshot committed at
  `drift_schemas/drift_schema_v1.json`, migration helpers in `test/generated_migrations/`.
  Tests assert `GeneratedHelper.versions == [1]` and that a fresh database matches the
  committed snapshot via `validateDatabaseSchema()`.*
  **Deviation (verified, keep it):** `dart run drift_dev schema generate` **must** be passed
  `--data-classes`. Flagless output emits raw `with TableInfo` (no type arguments), which
  `strict-raw-types: true` rejects — reproduced: 7 `strict_raw_type` warnings, `flutter analyze`
  exits 1. Drift's generated `// ignore_for_file: type=lint` header suppresses linter rules
  only, not analyzer warnings. The correct command is:
  `dart run drift_dev schema generate --data-classes drift_schemas/ test/generated_migrations/`
- [x] **T2.3** DAOs: `CourseDao`, `CardDao`, `ReviewLogDao`, `SettingsDao`.
  *Done — 4 DAOs with in-memory tests covering create/read/update/delete.*
- [x] **T2.4** Repository interfaces in `domain/`, Drift implementations in `data/`.
  *Done, and the constraint holds: grep confirms `lib/domain/` imports neither Drift nor
  Flutter.*
  Note: `AppDatabase` must import the domain enums and `ReviewStateConverter` directly,
  because `database.g.dart` is a `part of` the library and references them.*
- [ ] **T2.5** Plain-text (Markdown) deck import.
  *Verification: fixture file imports to expected card count.*
- [ ] **T2.6** Image storage convention: bytes on filesystem, paths in SQLite.
  *Verification: no BLOB column exists in the schema.*

## List 3 — Scheduler (highest-risk component)

> **GATE CLEARED.** The FSRS-5 constants and equations were verified against the canonical
> reference implementations and written into `design.md` → *Scheduler: FSRS-5 (verified)*.
> Do not re-derive them from `the_science_of_learning.md`; it supplies neither.
>
> Two things must be honoured by every task below:
> - `FACTOR` is **computed** from `DECAY` (`0.9^(1/DECAY) − 1`), never written as `0.2346`.
> - `enable_short_term` is **pinned explicitly** as a named constant. It changes both
>   same-day handling and the post-lapse clamp, so an implicit default silently diverges.

- [x] **T3.1** Port FSRS-5 to pure Dart: `S0`, `D0` (clamped `[1,10]`), `R(t,S)`, `I(r,S)`,
  difficulty update with linear damping + mean reversion, recall stability, lapse stability,
  short-term stability, and the 6-step dispatch order.
  *Done: `lib/domain/scheduling/fsrs5.dart`. `FACTOR` is computed from `DECAY`;
  `enable_short_term` is a pinned constructor default, not implicit. `lib/domain/` imports
  neither Flutter nor Drift (grep-verified).*
- [x] **T3.2** Validate against the reference vectors in `design.md`.
  *Done for the memory-state and first-review vectors — **and the gate caught a real error**.
  Three of four vectors now match exactly:*

  | Vector | Expected | Actual | Status |
  |---|---|---|---|
  | first-review stability | `[0.40255, 1.18385, 3.173, 15.69105]` | exact | ✅ |
  | first-review difficulty | `[7.1949, 6.48830527, 5.28243442, 3.22450159]` | exact | ✅ |
  | memory state, short-term **on** | `48.27115294` | `48.27115127` | ✅ |
  | memory state, short-term **off** | `48.065163` | `48.06515389` | ✅ |
  | interval history | `[0,4,14,44,125,328,0,0,6,14,31,65,130]` | exact | ✅ |

  **The `S^(-0.01)` short-term saturation term was NOT what either draft of the spec said.**
  First draft implied a `w19` slot FSRS-5 does not have; the correction removed the term
  entirely, which missed by `5.7e-3` — a plausible-looking wrong number that throws nothing.
  Solving for the exponent the vector implies gave `0.0100029`, i.e. the clamp floor. Both
  the code and `design.md` now record the corrected form with the evidence table.
- [x] **T3.6** Learning-step scheduling.
  *Done: `lib/domain/scheduling/scheduler.dart` drives the memory math with `new_`,
  `learning`, `review` and `relearning` states and configurable sub-day steps.
  **All five reference vectors now pass**, including the interval history — which reproduced
  exactly on the first run once the step machine existed.*
  Two configurations are kept deliberately separate:
  - `SchedulerConfig.singleStep` — one sub-day step. This is what the canonical vector
    encodes, because the raw reference algorithm graduates on the first successful learning
    review. The vector test uses this and nothing else.
  - `SchedulerConfig.ankiLearning` / `ankiRelearning` — Anki's `1m`→`10m`, relearn `10m`.
    This is what the app ships, and it changes the sequence *by design*, so it is validated
    by its own tests rather than by bending the canonical vector.
  **Schema v2:** `schedule_states.step` added, with a real `onUpgrade` that backfills
  existing rows to `0`. A migration test seeds a v1 database, upgrades it, and asserts both
  the column and the backfill. Snapshot committed as `drift_schemas/drift_schema_v2.json`.
  **Finding:** Drift returns `DateTime`s in **local** time, so an instant survives a
  round-trip but its representation does not. Tests must compare instants; day-boundary
  logic (T3.5) must normalise explicitly.
- [x] **T3.3** `dueCards(courseId, themeId, now, limit)` with interleaving option.
  *Done. Two pieces, split by concern:*
  - `CardDao.dueCards` does the SQL — a **two-hop join** (`schedule_states` →
    `cards` → `themes`; `schedule_states` links to `cards`, **not** to `themes`, which
    I got wrong on the first attempt). One query, no N+1 walk.
  - `orderDueCards` (`domain/scheduling/due_queue.dart`) is pure and does the sequencing.
    `blocked` groups by course then theme; `interleaved` round-robins across themes so
    adjacent cards come from different themes — the *contrast* is the mechanism, not the
    shuffling. Deterministic in both modes (no RNG), so sessions are reproducible.
  *Verified against real SQLite: all four repository tests pass, including one that
  asserts theme and course resolve through both hops.*
- [x] **T3.4** 85% target-band heuristic with hysteresis, marked as a heuristic in code.
  *Done: `domain/scheduling/accuracy_heuristic.dart`. Bands are widen (`≥0.95`),
  hold, tighten (`≤0.75`), with `insufficient` below a minimum sample so a couple of
  reviews cannot trigger a change. Only `again` counts as a miss — `hard` is still a
  successful recall, so honest grading is not punished.
  **It is labelled a heuristic everywhere it is exposed**, including in its own doc
  comment, and `AccuracyAdvice.explanation` says so in the text a user would see.
  It adjusts **new-card intake only**; review intervals stay FSRS's business.*
- [x] **T3.5** Timezone and day-boundary handling with a configurable day cutoff.
  *Done. `Scheduler.dayIndex` shifts local time by the cutoff (default 04:00) before
  taking the calendar date, so a 2am review belongs to the previous day. `elapsedDays`
  counts shifted calendar days rather than 24-hour blocks.
  A dedicated test proves a cutoff **cannot** change the canonical interval history,
  because every interval FSRS schedules lands on an exact multiple of a day — the vectors
  stay valid regardless of this setting.
  **Timezone fragility handled:** the cutoff tests construct local `DateTime`s rather than
  UTC ones, so they do not depend on the runner's zone. The vector tests remain UTC-based
  because they compare whole-day gaps only.
  Also recorded from T3.6: Drift returns `DateTime`s in local time, so instants compare
  correctly but representations do not.*

## List 4 — Initial test / onboarding

- [ ] **T4.1** Working-memory span mini-game + scoring.
  *Verification: deterministic score for a fixed input sequence.*
- [ ] **T4.2** Calibration probe (predict → perform → compare).
  *Verification: overconfident input sets the barrier default on.*
- [ ] **T4.3** Per-course prior-knowledge probe.
  *Verification: routes a course to `blocked` or `interleaved`.*
- [ ] **T4.4** Persist results → derive global `newCardsPerDay`, per-course
  `newCardsPerDay` + `interleaveMode`, barrier default.
  *Verification: `app_settings` and `courses` rows reflect the probe outcomes.*
- [ ] **T4.5** Onboarding UI, skippable and re-runnable from settings.
  *Verification: skipping applies documented defaults, not nulls.*

## List 5 — Card authoring

- [ ] **T5.1** Course CRUD.
- [ ] **T5.2** Theme CRUD nested under a course.
- [ ] **T5.3** Card editor with front/back fields and live LaTeX preview.
  *Verification: `$...$` renders to a formula widget as the user types.*
- [ ] **T5.4** LaTeX widget wrapper over `flutter_math_fork` with an error fallback.
  *Verification: malformed TeX renders a readable error, never crashes or blanks the card.*
- [ ] **T5.5** Attach image to card (pick → downscale → store locally).
  *Verification: round-trips across app restart.*
- [ ] **T5.6** Card list grouped Course → Theme with due counts.
  *Verification: counts match `dueCards` output for the same clock.*
- [ ] **T5.7** Search/filter across cards.
  *Verification: finds cards by front text and by course.*

## List 6 — Review engine

- [ ] **T6.1** Session builder: course/theme selection, due count, blocked vs interleaved.
- [ ] **T6.2** Review screen with a single focus and the 4±1 content limit (`:536-539`).
  *Verification: no competing panels; one question on screen at a time.*
- [ ] **T6.3** Forced Generation Barrier (configurable): reveal disabled until an attempt
  exists (`:1155-1156`).
  *Verification: reveal control is provably inert before an attempt.*
- [ ] **T6.4** Rating UI (Again / Hard / Good / Easy) writing to the scheduler.
- [ ] **T6.5** Record interaction signals: latency, hint use, barrier completion.
  *Verification: signals recorded for calibration warnings only — they never mutate a grade.*
- [ ] **T6.6** Write `ReviewLog`, update `ScheduleState`, advance the queue.
  *Verification: append-only — logs are never updated or deleted.*
- [ ] **T6.7** Session summary screen (honest stats belong here, not during review).

## List 7 — Theming

- [ ] **T7.1** Light/dark palettes, Material 3 seed color.
- [ ] **T7.2** Persist `ThemeMode`, apply at app root.
  *Verification: survives restart.*
- [ ] **T7.3** Audit every screen in both modes.
  *Verification: golden tests for LaTeX on dark — the specific contrast risk.*

## List 8 — AI settings and image → flashcards (riskiest, last)

- [ ] **T8.1** Settings: base URL (default `https://api.synthetic.new/v1`) + API key →
  secure storage. **Confirm the auth header shape at integration.**
- [ ] **T8.2** "Verify connection" → `GET /models`.
  *Verification: a 401 leaves the feature disabled with a clear message.*
- [ ] **T8.3** Model picker reading `input_modalities` + `supported_features`; badge
  vision-capable models. Do not hardcode model names.
  *Verification: models lacking `"image"` are visibly non-selectable for image import.*
- [ ] **T8.4** Persist the selected model; feature stays disabled until verified.
  *Verification: feature cannot be reached without a verified configuration.*
- [ ] **T8.5** Course-selection gate before upload, enforced in the flow.
  *Verification: upload screen is unreachable without a selected course.*
- [ ] **T8.6** Image capture/pick → downscale → base64.
- [ ] **T8.7** Prompt builder demanding strict JSON; `POST /chat/completions`.
- [ ] **T8.8** Error handling: 401, timeout, non-JSON body, valid JSON with wrong shape,
  partial card lists.
  *Verification: fixture tests cover each malformed case.*
- [ ] **T8.9** Mandatory review/edit screen before persistence.
  *Verification: no card reaches the database without user approval.*
- [ ] **T8.10** Redaction: the key and image payloads are never logged or exported.
  *Verification: scan logs and export output for both.*

## List 9 — Verification gates (run alongside, not at the end)

- [ ] **T9.1** Scheduler unit tests against reference vectors — highest value in the app.
- [ ] **T9.2** Repository tests on in-memory Drift.
- [ ] **T9.3** JSON-parsing tests against malformed model output.
- [ ] **T9.4** Golden tests for LaTeX in light and dark.
- [ ] **T9.5** End-to-end: create course → add card → review → log written.

## List 10 — Polish and release

- [ ] **T10.1** Empty, error, and loading states.
- [ ] **T10.2** Offline guarantee test: airplane mode, full flow works minus AI.
- [ ] **T10.3** Local export/backup. No cloud path.
- [ ] **T10.4** App icon, splash, versioning.
- [ ] **T10.5** Release build and signing.

---

## Explicitly dropped from earlier drafts

| Dropped | Reason |
|---|---|
| iOS, web, desktop targets | Decision 3: Android only |
| AI grading of answers | Decision 2: disabled |
| Chained-PR slicing | No remote (T0.2): local commits only; revisit if a remote is added |
| Learning-style personalization | VAK neuromyth, `:932-958` |
| Highlighting / summarization / re-reading | Dunlosky LOW ratings, `:899-903` |
| `flutter_tex` | WebView dependency, offline-hostile |
| SM-2 scheduler | Decision 1: native FSRS-5 port |

## Next step

Execute **T2.1** (Drift tables and schema).

Do not start List 3 until the FSRS-5 constants are confirmed against the canonical
implementation — that single fact is the gate for the app's core value.

## Resolved decisions

1. **Flutter version pinning — resolved.** CI is the authoritative pin:
   `flutter-version: 3.47.7` in `.github/workflows/ci.yml`. The local `.puro.json` remains
   machine-local because puro self-excludes it via `.git/info/exclude`. Upgrading Flutter
   requires updating the workflow in the same change.

## Open decisions

1. **FSRS-5: hand-port vs. the official Dart `fsrs` package.** Verification found an
   official package (`fsrs` 2.0.1, `open-spaced-repetition/dart-fsrs`, 65 stars, not
   archived, last pushed 2025-06-20). It is **not** a drop-in: its changelog says 2.0.0 is
   FSRS-6, it does not contain the FSRS-5 weight `0.40255`, and its own interval-history
   test expects `[0,4,14,45,135,372,0,0,2,5,10,20,40]` which **diverges** from the canonical
   FSRS-5 vector `[0,4,14,44,125,328,0,0,6,14,31,65,130]` from the 4th element onward.
   Depending on it means adopting FSRS-6, not FSRS-5, with unverified vector behaviour.
   Not chosen yet — T3.1 is blocked on this choice.
