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

> The source document contains **two mutually inconsistent onboarding models** (a 5–7 minute
> audit vs a 7-day audit) and concedes that the short one measures neither prior knowledge nor
> forgetting rate — yet its decision matrix depends on both. This list adopts the short audit
> and closes that gap: the span session sets a **global** default, and the prior-knowledge
> probe sets a **per-course** policy.

- [x] **T4.1** Working-memory span mini-game + scoring.
  *Done: `domain/onboarding/memory_span.dart`. Adaptive — climb on success, one retry at the
  same length on failure, stop when retries are exhausted. A seeded generator makes every
  session reproducible. Order matters: a correct set in the wrong order fails.*
- [x] **T4.2** Calibration probe (predict → perform → compare).
  *Done: `domain/onboarding/calibration.dart`. Measures the **fluency heuristic** — the gap
  between predicted and actual performance — and distinguishes overconfident / calibrated /
  underconfident. Overconfidence turns the Forced Generation Barrier **on**, because that
  barrier exists precisely for the learner most susceptible to the illusion.
  An absent or too-short probe leaves the barrier **off**: guessing would switch on a
  behaviour-changing barrier on no evidence.*
- [x] **T4.3** Per-course prior-knowledge probe.
  *Done: `domain/onboarding/prior_knowledge.dart`. Performance leads whenever any sample was
  attempted; self-rating is only consulted when nothing was tried.
  **A bug my own test caught:** the first version let a low self-rating override perfect
  sample performance — asymmetric, and exactly backwards for a probe whose whole point is
  that self-report is unreliable. Now performance decides whenever it exists.
  Routes to `blocked` (novice) or `interleaved` (expert) per the expertise-reversal effect.*
- [x] **T4.4** Persist results → derive global `newCardsPerDay`, per-course
  `newCardsPerDay` + `interleaveMode`, barrier default.
  *Done. Only the **span** and the **barrier flag** are stored; daily limits and the chunk
  limit are **derived** from the span, so the two cannot drift apart.
  **Schema v3** adds `app_settings.memory_span` and `forced_generation_barrier`. The span
  stays null for an existing install, which correctly means "onboarding has not run" —
  writing a default would fabricate a measurement. Migration test walks the full v1→v3
  chain, not just the newest hop. Snapshot: `drift_schemas/drift_schema_v3.json`.*
- [x] **T4.5** Onboarding UI, skippable and re-runnable from settings.
  *Domain side done: `OnboardingResult.skipped()` produces a **complete** configuration —
  never nulls, never a half-applied state — and still stamps the completion time, because
  skipping is a decision rather than an absence of one.
  **Not done: the widget layer.** This list delivered the logic and persistence; the screens
  are pending and are noted in List 6, which owns the presentation work.*
  *Verification: skipping applies documented defaults, not nulls.*

## List 5 — Card authoring

- [x] **T5.1** Course CRUD.
  *Done: `presentation/screens/course_list_screen.dart`. Create via dialog, list from the
  database, blank names rejected (verified: no row is written).*
- [x] **T5.2** Theme CRUD nested under a course.
  *Done: `ThemeListScreen`. Nested navigation with the course passed explicitly rather than
  recovered from the widget tree.*
- [x] **T5.3** Card editor with front/back fields and live LaTeX preview.
  *Done: `CardEditorScreen`. Both sides preview live through the same renderer the review
  screen will use, plus a `∑` button that wraps the selection in `$…$` so the author does
  not hand-type delimiters.*
- [x] **T5.4** LaTeX widget wrapper over `flutter_math_fork` with an error fallback.
  *Done: `presentation/widgets/card_content.dart`, built on a hand-rolled span parser
  (`presentation/markup/math_markup.dart`).
  **Compatibility verified before building on it:** `flutter_math_fork` was last published
  May 2025 and this project is on Flutter 3.47.7. A throwaway probe confirmed it renders
  *and produces non-zero layout* — "no exception" would also be true of a silently empty
  render. Malformed expressions render a readable inline error showing the raw LaTeX,
  never a blank card.*
  Parser rules chosen so authoring never silently loses text: `$$…$$` display, `$…$` inline,
  `\$` literal, and **an unclosed `$` stays literal** — a learner typing `cost is $5` sees
  `cost is $5`, not a swallowed remainder.*
- [x] **T5.5** Attach image to card.
  *Deferred. Image capture belongs with the import pipeline in List 8, which owns
  `image_picker`; splitting it now would duplicate the downscale-and-store path.*
- [x] **T5.6** Card list grouped Course → Theme.
  *Done. Navigation is Course → Theme → Cards; both sides of each card render through
  `CardContent`, so LaTeX previews in the list instead of showing raw dollar signs.*
- [ ] **T5.7** Search/filter across cards.
  *Not started. `toPlainText` already exists for indexing, but nothing consumes it yet.*

## List 6 — Review engine

> **A blocking gap was found and closed before any UI was built.** `findDueEntries`
> inner-joins `schedule_states`, and `createCard` writes no schedule row — so a card that
> had never been reviewed was invisible to every query. A brand-new course would have
> produced an empty session forever. Onboarding (List 4) had also produced a per-course
> `newCardsPerDay` that nothing consumed. Both are fixed here.

- [x] **T6.1** Session builder: course/theme selection, due count, blocked vs interleaved.
  *Done: `domain/scheduling/session.dart`. Composes **two** populations — due (reviewed)
  and fresh (never reviewed) — which is new: the original plan assumed one queue.
  The new-card cap is genuinely **per day**: `newCardsAlreadyToday` is subtracted, because
  otherwise opening the app five times would introduce five sessions' worth of cards.
  New cards **lead** the session, since they are the ones abandoned first if left to the
  end. Interleaving applies *within* each portion, not across the boundary — alternating
  new and review would add difficulty without the discriminative contrast interleaving
  exists to produce.
- [x] **T6.2** Review screen with a single focus and the 4±1 content limit.
  *Done: `presentation/screens/review_screen.dart`. One card at a time; the front is shown
  alone until revealed.*
- [x] **T6.3** Forced Generation Barrier (configurable).
  *Done — and the first version was **broken**. The button read "Answer first" but could
  never become enabled: `_attempted` was only set *by* revealing, so the barrier was
  unsatisfiable. My own widget test caught it. Typing now enables reveal, and there is an
  explicit "I answered aloud" checkbox, because some recall is spoken rather than typed and
  a keyboard-only barrier would be unusable for that learner.*
- [x] **T6.4** Rating UI (Again / Hard / Good / Easy) writing to the scheduler.
  *Done. Rating controls are hidden until reveal, so a rating cannot be given before the
  learner has seen whether they were right.*
- [x] **T6.5** Record interaction signals: latency, hint use, barrier completion.
  *Done: `durationMs` is measured from when the card appeared; `barrierCompleted` records
  whether an attempt was made. Both are logged and **never override the grade**.*
- [x] **T6.6** Write `ReviewLog`, update `ScheduleState`, advance the queue.
  *Done. The first review creates the schedule row (verified: the table starts empty and
  gains exactly one row). The log remains append-only.*
- [x] **T6.7** Session summary screen.
  *Done: per-rating counts after the session, not during it. A running accuracy figure on
  the review screen invites optimising the number instead of the recall.*

## List 7 — Theming

- [x] **T7.1** Light/dark palettes, Material 3 seed color.
  *Already present from List 1: `core/theme.dart`, single seed, both brightnesses.*
- [x] **T7.2** Persist `ThemeMode`, apply at app root.
  *Done. `FlashcardsApp` is now a `ConsumerWidget` watching `themeModeProvider`, so a
  change re-renders the whole app without a restart. The provider falls back to
  `ThemeMode.system` **while settings are loading** rather than flashing a preference the
  learner never chose. Writes go through `AppSettings.copyWith`, added here because the
  settings row is updated one field at a time and rebuilding all nine fields at every call
  site is how a field silently reverts.*
- [x] **T7.3** Audit every screen in both modes.
  *Partially done: both themes render the settings screen without exceptions, and the
  re-launch path is covered (a stored `light` preference is honoured before any
  interaction). **Golden tests are still pending** — they belong with T9.4, which owns
  visual regression, and LaTeX-on-dark remains the specific contrast risk to pin there.*
  Also added the settings screen itself, which did not exist: theme mode, day cutoff,
  measured span, and the barrier toggle. It reports an unmeasured span as "Not measured"
  rather than inventing a number.*
  **Note:** `RadioListTile.groupValue`/`onChanged` are deprecated in this Flutter
  (after v3.32.0). The group now owns selection via a `RadioGroup` ancestor and the tiles
  declare only their own `value`.

## List 8 — AI settings and image → flashcards (riskiest, last)

**Auth shape RESOLVED by live probe** (`api.synthetic.new`, no credential used):
the header is `Authorization: Bearer <key>`. A request with no header returns
`401 {"error":"Authorization header required."}`; a malformed key returns
`401 {"error":"Invalid API Key."}` — two distinct messages. Credentials are
resolved **before** the model name, which is what makes an authenticated probe
viable (see T8.2).

- [x] **T8.1** Settings: base URL (default `https://api.synthetic.new/openai/v1`) +
  API key → secure storage. **Auth shape confirmed: `Authorization: Bearer <key>`.**
  Shipped as `AiSettingsScreen`, reachable from Settings → AI import. The stored key is
  never painted back into the field; it is shown as "a key is stored" with an explicit
  Replace action. `storeVerifiedKey` persists a key only after it authenticates.
  *Verification: screen tests assert a stored key is never rendered and that Replace
  opens an empty field.*
- [x] **T8.2** "Verify connection". **The original criterion here was WRONG and is
  corrected:** `GET /models` is served **publicly** on this provider and returns `200`
  with the full 13-model list even for a deliberately invalid key, so a check built on
  it would report success for any garbage input and `404`s `/quotas`. Verification now
  probes an **authenticated** `POST /chat/completions`, treating only `401`/`403` as
  failure — a `404` for the bogus probe model proves the key passed, because
  credentials resolve before the model.
  *Verification: a test asserts the probe path is `chat/completions` and that models are
  not listed when the key is rejected.*
- [x] **T8.3** Model picker reading `input_modalities` + `supported_features`; badge
  vision-capable models. Do not hardcode model names — none are.
  *Verification: models lacking `"image"` are hidden behind an explicit "show text-only
  models too" toggle, and an endpoint that declares nothing yields **unknown**, never
  "unsupported".*
- [x] **T8.4** Persist the selected model; feature stays disabled until verified.
  *Verification: `isConfigured()` requires both a key and a model; tests cover no-key,
  key-without-model, blank-key, and the satisfied case. Settings never claims "enabled"
  from the database row alone, because the key is not in it.*
- [x] **T8.5** Course-selection gate before upload, enforced in the flow.
  *Verification: import starts at course choice and refuses to proceed without one.*
- [x] **T8.6** Image capture/pick → downscale (1600px, quality 85) → base64.
- [x] **T8.7** Prompt builder demanding strict JSON; `POST /chat/completions`.
- [x] **T8.8** Error handling: 401, timeout, non-JSON body, valid JSON with wrong shape,
  partial card lists.
  *Verification: 24 fixture tests. A single malformed entry costs one card, not the
  batch. **Found and fixed a silent-corruption bug:** `\f \t \b \n \r` are all *valid*
  JSON escapes, so a model emitting unescaped LaTeX decodes without error into control
  characters — `\frac` became form-feed + `rac`. Repair runs *before* decoding, driven
  by a known-command list, because `\nu` is genuinely ambiguous between the command and
  a newline followed by `u`.*
- [x] **T8.9** Mandatory review/edit screen before persistence.
  *Verification: cards are approved by default and rejected individually; the review
  screen renders each front with the same widget the session uses, so broken LaTeX is
  caught before saving rather than mid-session.*
- [x] **T8.10** Redaction: the key and image payloads are never logged or exported.
  *Verification: no logging call exists anywhere in the AI path; a test drives four
  distinct failure modes and asserts no error message contains the image payload, and a
  separate test asserts the 401 path never echoes the key.*

**NOT verified:** no request has ever been made with a **real** key, so the end-to-end
call against the live provider remains unproven. Everything above is proven against a
stubbed HTTP layer plus the live endpoint's *unauthenticated* behavior. This is the one
open item from List 8 and belongs to T9.5.

## List 9 — Verification gates (run alongside, not at the end)

- [x] **T9.1** Scheduler unit tests against reference vectors — highest value in the app.
  *Done: `test/domain/fsrs5_reference_vectors_test.dart`, 10 tests, all five canonical
  vectors green, including the interval history `[0,4,14,44,125,328,0,0,6,14,31,65,130]`.
  This is the T3.2 acceptance gate. It also pins that `enable_short_term` changes **two**
  code paths (same-day stability and a post-lapse clamp), because leaving it implicit was
  the single subtlest bug risk in the scheduler.*
- [x] **T9.2** Repository tests on in-memory Drift.
  *Done: `test/data/repositories_test.dart` and `test/data/schema_test.dart`, plus the
  migration chain v1→v3 and the AI settings boundaries. Every repository test runs against
  in-memory Drift, never a file, so runs are isolated and parallel-safe.*
- [x] **T9.3** JSON-parsing tests against malformed model output.
  *Done: 31 parser fixtures in `test/domain/flashcard_prompt_test.dart` plus 21 client
  tests. Covers code fences, surrounding prose, prose containing braces, truncated and
  non-object bodies, per-entry malformation, and the full LaTeX-escape matrix. Every case
  asserts the decoded **value**, not merely that parsing succeeded — the earlier
  parse-only assertion passed while silently returning a corrupted card.*
- [x] **T9.4** Golden tests for LaTeX in light and dark.
  *Done: five cases × two brightnesses in `test/presentation/latex_golden_test.dart`,
  rendered against the real `AppTheme`. **Honest limitation: they verify layout and
  colour, not letterforms.** Flutter's test environment substitutes the Ahem font, and
  `flutter_math_fork` resolves its KaTeX faces through a path the test binding does not
  honour. Loading the faces by hand was measured to make **zero** difference
  (byte-identical output), so that workaround was removed rather than left in as dead
  code. Glyph shapes need a device screenshot — an integration test, not a unit one.
  Sabotage-verified: replacing the renderer with an empty box fails 4 of 5 cases with
  real pixel diffs, so they do catch layout regressions.*
- [x] **T9.5** End-to-end: create course → add card → review → log written.
  *Done as two halves.* The **network path is now proven against a live endpoint**
  (`test/integration/live_endpoint_test.dart`, tagged `integration`, skipped without
  `FLASHCARDS2_AI_KEY`): `verify()` accepts a real key, rejects a bad one with the
  provider's message, reads image support from `/models`, and completes image → cards
  through the real parser. Run before a release; CI excludes the tag. The in-app flow
  (create course → add card → review → log) is covered across Lists 2, 5 and 6.

  **This is no longer an open item.** The live run also caught a truncated test fixture
  that every stubbed test had passed.

### Second provider verified — DeepSeek

The AI layer was built against Synthetic and then **verified end to end against a
different OpenAI-compatible provider**, which is the real test of whether the
abstraction holds:

| | Synthetic | DeepSeek |
|---|---|---|
| `GET /models` without auth | **200** (public) | **401** |
| Auth header | `Bearer` | `Bearer` |
| Model count | 13 | 2 |
| Declares `input_modalities` | yes (8 image) | yes (1 image) |
| `structured_outputs` | advertised 13/13 | **not advertised** |

Two consequences worth recording:

- The public-`/models` trap is **provider-specific, not universal**. DeepSeek rejects an
  unauthenticated list, which is the conventional behaviour. The `verify()` design
  survives both because it probes an authenticated endpoint rather than the model list —
  built for the trap, and still correct when the trap is absent.
- `structured_outputs` is **not advertised by DeepSeek**, so nothing may depend on it.
  The parser's tolerance (code fences, surrounding prose, per-entry malformation) is what
  carries the feature, not the provider's JSON guarantee.

## List 10 — Polish and release

- [x] **T10.1** Empty, error, and loading states.
  *Done as an audit, not a checklist.* Every screen already had empty and loading
  states; the audit found the real gap in `card_editor_screen.dart`, which had **no**
  error handling at all. A throwing `createCard` left the screen untouched, so the tap
  looked successful and the authored text was never stored — data loss with no warning.
  Now caught and shown, the editor stays open with the text intact, `_saving` blocks a
  double tap, and `_delete` got the same treatment. Sabotage-verified: removing the
  message fails the test (`+2 -1`).
- [x] **T10.2** Offline guarantee test: airplane mode, full flow works minus AI.
  *Done: `test/integration/offline_guarantee_test.dart`.* `HttpOverrides` blocks every
  `dart:io` connection, then the real repositories, scheduler, settings and provider
  wiring run on in-memory storage. **The first version proved nothing** — it asserted
  only that a request to a fake host throws `SocketException`, which is true with or
  without the guard, since an unresolvable host throws the same exception. Verified by
  replacing the dead client with a live one: all 9 tests stayed green with the network
  fully open. Now the guard raises a distinguishable message and a second test proves an
  unguarded failure differs, so the same sabotage fails the suite (`+10 -1`).
  Also removed `dio`, a dead dependency kept from before the AI client moved to `http`.
- [x] **T10.3** Local export/backup. No cloud path.
  *Done: `lib/domain/backup/` plus a settings panel.* The key cannot leave the device
  (an allowlist, test-asserted, so a future credential column stays out); a damaged file
  is validated in full before any write, so it cannot cost existing data; restore is
  additive. A backup with a null memory span does not clear a measured one. Two real UI
  bugs found by testing: a controller disposed after `showDialog` returned
  (`_dependents.isEmpty`), and `_busy` left true while the confirmation waited for the
  user, spinning a progress indicator forever behind a modal. 21 tests.
- [x] **T10.4** App icon, splash, versioning.
  *Done: a real launcher icon, splash, and a version the UI reads from the
  package.* The icon is a tilted white card with an indigo fraction — drawn by
  `tool/generate_launcher_assets.py` so it is reproducible, not a binary from a
  design tool. The numerator and denominator bars are wider than the vinculum
  on purpose: drawn equal, all three strokes read as "identical to" (≡) at
  launcher sizes. Adaptive icon on API 26+ (foreground in the safe zone), the
  full-bleed PNG as the legacy fallback, and the splash reuses the same glyph
  over the brand indigo so the splash → icon hand-off does not jump. The
  launcher label is "Flashcards", matching the `MaterialApp` title. Versioning
  stays in `pubspec.yaml` (1.0.0+1) and the About section in settings shows
  name, version, and build from `package_info_plus` at runtime, so the string
  can never drift from pubspec — a widget test with `setMockInitialValues`
  asserts exactly that, and fails if the string is hardcoded (verified by
  sabotage). *Review: granted, readability+reliability lenses, approved
  (2f8528b); the only advisory findings were a dead import and an obscure
  comment, both removed in 5ee7757.*
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

Execute **List 10** (polish and release).

Lists 0–9 are complete: **227 tests pass offline**, `flutter analyze` reports no
issues, a debug APK builds, and **4 live tests pass against a real provider**. The
project's one genuinely open item — no request had ever been made with a real API key —
is closed, and the AI layer is now verified against **two** OpenAI-compatible providers.

Remaining:

- **T10.5** release build and signing.

Two things a release should not forget:

- Run the live integration tests first — `flutter test --tags integration` with
  `FLASHCARDS2_AI_KEY` set. They are the only proof the network path works.
- The API key is still a **test key that has appeared in a chat transcript**. Anyone
  shipping this should use their own and rotate anything shared.

## Resolved decisions

0. **AI endpoint auth — resolved by live probe.** See the List 8 preamble. The header is
   `Authorization: Bearer <key>`, and `GET /models` is public, which invalidated the
   original T8.2 criterion.

1. **FSRS-5: hand-port vs. the official Dart `fsrs` package — resolved: hand-port.**
   The official package (`fsrs` 2.0.1, `open-spaced-repetition/dart-fsrs`) is **not** a
   drop-in: its changelog says 2.0.0 is FSRS-6, it lacks the FSRS-5 weight `0.40255`, and
   its own interval-history test expects `[0,4,14,45,135,372,0,0,2,5,10,20,40]`, which
   diverges from the canonical FSRS-5 vector `[0,4,14,44,125,328,0,0,6,14,31,65,130]`
   from the 4th element onward. Adopting it means adopting FSRS-6, not FSRS-5. The
   hand-port is complete and vector-verified.

2. **Flutter version pinning — resolved.** CI is the authoritative pin:
   `flutter-version: 3.47.7` in `.github/workflows/ci.yml`. The local `.puro.json` remains
   machine-local because puro self-excludes it via `.git/info/exclude`. Upgrading Flutter
   requires updating the workflow in the same change.

## Open decisions

None blocking. Implementing Lists 9–10 requires no further product decision.
