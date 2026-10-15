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

**`single-pr` is impossible right now.** No git remote is configured, so no PR mechanism
exists — pull requests cannot be opened, and `chained-pr` / `work-unit-commits` skills are
not applicable until a remote exists.

Consequence, recorded honestly:

- Work proceeds as **local work-unit commits**, one per list or per coherent sub-list.
- The `docs/app-plan` branch already exists and holds this plan.
- **Open decision:** once a remote is added, the ~4,200-line forecast exceeds the ~400-line
  review budget, so a chain strategy (`stacked-to-main` or `feature-branch-chain`) becomes
  required. Resolve the `chained-pr` skill at that point. This is not addressed yet.

Feature-document mirror: `odd/local-first-flashcards/tasks` in Engram, plus this file.

---

## List 0 — Bootstrap

- [ ] **T0.1** Branch for the plan (`docs/app-plan`). *Verification: branch exists, plan committed.*
- [ ] **T0.2** Configure a git remote, or record the decision to stay local-only.
  *Verification: `git remote -v` non-empty, or open decision explicitly accepted.*

## List 1 — Foundation

- [ ] **T1.1** `flutter create --platforms=android --org <org> .`
  **Android only** — do not scaffold iOS, web, or desktop.
  *Verification: `android/` exists, `ios/ web/ linux/ windows/ macos/` do not.*
- [ ] **T1.2** Add dependencies: `drift`, `sqflite`, `riverpod`, `freezed`, `dio`,
  `flutter_secure_storage`, `flutter_math_fork`, `image_picker`.
  *Verification: `flutter pub get` clean; no `flutter_tex` in `pubspec.yaml`.*
- [ ] **T1.3** `very_good_analysis` + strict `analysis_options.yaml`.
  *Verification: `flutter analyze` exits 0 with zero infos.*
- [ ] **T1.4** Folder skeleton `data/ domain/ presentation/ core/`.
  *Verification: directories exist and are declared in the lint config.*
- [ ] **T1.5** CI: `flutter analyze` + `flutter test` on push.
  *Verification: pipeline runs green on the bootstrap commit.*

## List 2 — Persistence

- [ ] **T2.1** Drift tables: `courses`, `themes`, `cards`, `schedule_states`,
  `review_logs`, `app_settings`.
  *Verification: generated code compiles; schema dump committed.*
- [ ] **T2.2** Migration v1 + schema export test.
  *Verification: migration test passes from empty DB.*
- [ ] **T2.3** DAOs: `CourseDao`, `CardDao`, `ReviewLogDao`, `SettingsDao`.
  *Verification: in-memory DB tests cover create/read/update/delete each.*
- [ ] **T2.4** Repository interfaces in `domain/`, Drift implementations in `data/`.
  *Verification: `domain/` imports neither Flutter nor Drift.*
- [ ] **T2.5** Plain-text (Markdown) deck import.
  *Verification: fixture file imports to expected card count.*
- [ ] **T2.6** Image storage convention: bytes on filesystem, paths in SQLite.
  *Verification: no BLOB column exists in the schema.*

## List 3 — Scheduler (highest-risk component)

- [ ] **T3.1** Port FSRS-5 to pure Dart: initial stability, initial difficulty (clamped
  `[1,10]`), difficulty update with mean reversion, retrievability, stability increase,
  stability after lapse, same-day update.
  **Confirm `F = 19/81` and `D = 0.5` against the canonical implementation before writing
  the equations.** Do not reconstruct them from `the_science_of_learning.md`.
  *Verification: symbols compile with no Flutter import.*
- [ ] **T3.2** Validate against published FSRS reference vectors.
  *Verification: all reference vectors match within tolerance — this is the acceptance gate
  for the whole list; do not proceed past a failure.*
- [ ] **T3.3** `dueCards(courseId, themeId, now, limit)` with interleaving option.
  *Verification: tests cover due ordering and blocked vs interleaved selection.*
- [ ] **T3.4** 85% target-band heuristic with hysteresis, marked as a heuristic in code.
  *Verification: unit tests for widen / hold / tighten branches.*
- [ ] **T3.5** Timezone and day-boundary handling with a configurable day cutoff.
  *Verification: tests around midnight and DST boundaries.*

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
| Chained-PR slicing | No remote configured; revisit when one exists |
| Learning-style personalization | VAK neuromyth, `:932-958` |
| Highlighting / summarization / re-reading | Dunlosky LOW ratings, `:899-903` |
| `flutter_tex` | WebView dependency, offline-hostile |
| SM-2 scheduler | Decision 1: native FSRS-5 port |

## Next step

Execute **T0.2** (remote decision) and **T1.1** (Android-only scaffold), then **T2.1**.

Do not start List 3 until the FSRS-5 constants are confirmed against the canonical
implementation — that single fact is the gate for the app's core value.
