# Technical Explanation: Flashcards2 Architecture & Internal Mechanisms

## 1. Executive Summary & Core Philosophy

**Flashcards2** is an offline-first, single-user flashcard application built specifically for Android using Flutter and Dart. Unlike conventional spaced-repetition applications (often based on naive SM-2 ladders or cloud synchronization services), Flashcards2 is engineered around principles from cognitive science—specifically derived from the foundational document [`the_science_of_learning.md`](../the_science_of_learning.md).

### Foundational Principles
1. **Local-First & Zero Telemetry:** There are no user accounts, no cloud backend, and no tracking. All data is persisted locally in an embedded SQLite database via Drift.
2. **Defeating the Fluency Illusion:** Learners routinely confuse familiarity with mastery (the "fluency illusion"). Flashcards2 counters this through generative recall barriers and anti-passive review mechanics.
3. **Pure-Dart Domain Layer:** All business logic, memory algorithms, and session planning live in a pristine, pure-Dart domain layer with zero dependencies on Flutter or database frameworks, guaranteeing deterministic unit testing.
4. **FSRS-6 Scheduling with Verified Rollback:** Scheduling relies on the official `fsrs` package (FSRS-6) consumed behind a pure-Dart anti-corruption layer, with a frozen native FSRS-5 port retained in-tree as the verified rollback engine — never a heuristic interval ladder.

---

## 2. High-Level Architecture & Layer Separation

The application strictly implements clean architecture with inward-pointing dependencies:

```
┌─────────────────────────────────────────────────────────────┐
│                     Presentation Layer                      │
│        (Flutter Widgets, Riverpod Providers, Theming)       │
└──────────────────────────────┬──────────────────────────────┘
                               │ depends on
┌──────────────────────────────▼──────────────────────────────┐
│                        Domain Layer                         │
│   (Entities, Repository Interfaces, FSRS-6, Session Engine)  │
│          *** Pure Dart: Zero Flutter / Drift ***            │
└──────────────────────────────▲──────────────────────────────┘
                               │ implemented by
┌──────────────────────────────┴──────────────────────────────┐
│                         Data Layer                          │
│     (Drift SQLite DB, DAOs, HTTP AI Client, Secure Storage) │
└─────────────────────────────────────────────────────────────┘
```

### 2.1 Layer Responsibilities

*   **`lib/domain/` (Pure Dart):**
    *   Houses domain models (`Course`, `Theme`, `Card`, `CardSchedule`, `ReviewLog`, `AppSettings`).
    *   Contains the scheduling engine — the **FSRS-6 adapter** (`fsrs6_adapter.dart`, an ACL over `package:fsrs` 2.0.1), the frozen **FSRS-5 rollback port** (`fsrs5.dart`), the `MemoryEngine` contract, and session queue engines (`due_queue.dart`, `session.dart`, `global_session.dart`).
    *   Defines abstract repository contracts (`CardRepository`, `CourseRepository`, `ReviewLogRepository`, `SettingsRepository`, `AiClient`).
    *   Maintains cognitive calibration logic (working-memory span, metacognitive probe, prior knowledge classification).
*   **`lib/data/` (Persistence & Infrastructure):**
    *   Implements domain repositories using **Drift** (SQLite).
    *   Manages database schema, data access objects (DAOs), and migrations (`v1` → `v3`).
    *   Handles platform secrets (`SecureApiKeyStore` backed by `flutter_secure_storage` / Android Keystore).
    *   Implements the OpenAI-compatible REST client (`OpenAiCompatibleClient`).
*   **`lib/presentation/` (UI & Application State):**
    *   Riverpod code-generated providers (`providers.dart`) providing dependency injection and reactive state feeds.
    *   UI screens: `CourseListScreen`, `CardListScreen`, `CardEditorScreen`, `ReviewScreen`, `OnboardingScreen`, `SettingsScreen`, `AiSettingsScreen`, `ImageImportScreen`.
    *   Native TeX parsing and rendering via `CardContent` using `flutter_math_fork`.
*   **`lib/core/`:**
    *   Material 3 theme configuration (`AppTheme.light`, `AppTheme.dark`) using a single seed color.

---

## 3. Spaced Repetition Engine: FSRS-6 live, FSRS-5 frozen rollback

> [!IMPORTANT]
> **Since 2026-10-17 the live engine is FSRS-6**, provided by `package:fsrs` 2.0.1 behind the `Fsrs6SchedulerAdapter` anti-corruption layer (`fsrs6_adapter.dart`). The domain `Scheduler` (`scheduler.dart`) still owns the step state machine, due arithmetic, and the 4 AM day-cutoff; the package only advances $(S, D)$ and maps stability to intervals, behind the `MemoryEngine` contract (`memory_engine.dart`). Everything below documents the **frozen FSRS-5 port** (`fsrs5.dart`), retained as the verified rollback engine — its integration through `Scheduler` is gated by the `ROLLBACK GATE` test in `interval_history_test.dart`. Migration plan, decisions, and evidence: `docs/fsrs6_migration_plan.md`.

The scheduling core is located in `lib/domain/scheduling/` and is split into the memory math (the FSRS-6 adapter, or the frozen `fsrs5.dart`) and the step machine (`scheduler.dart`).

### 3.1 Two-Dimensional Memory Model

FSRS-5 models memory using two core continuous variables:
*   **Stability ($S$):** The time (in days) required for the probability of recall (Retrievability $R$) to fall from 100% to 90%.
*   **Difficulty ($D \in [1, 10]$):** The intrinsic difficulty of the card, where 1 is simplest and 10 is most complex.

### 3.2 Mathematical Formulas

1.  **Retrievability ($R$):**
    $$R(t, S) = \left(1 + \text{FACTOR} \cdot \frac{t}{S}\right)^{\text{DECAY}}$$
    *   $\text{DECAY} = -0.5$ (fixed power-law decay in FSRS-5).
    *   $\text{FACTOR} = 0.9^{1/\text{DECAY}} - 1 = \frac{19}{81} \approx 0.2345679$.
    *   By construction, when elapsed time $t = S$, $R(S, S) = 0.90$.

2.  **Initial Values on First Review:**
    For grade $G \in \{1, 2, 3, 4\}$ ($\text{Again}=1, \text{Hard}=2, \text{Good}=3, \text{Easy}=4$):
    *   $S_0(G) = \max(w_{G-1}, 0.1)$
    *   $D_0(G) = w_4 - e^{w_5 \cdot (G - 1)} + 1$ (clamped to $[1, 10]$)

3.  **Difficulty Transition:**
    $$\Delta D = -w_6 \cdot (G - 3)$$
    $$\text{Damping}(\Delta D, D) = \Delta D \cdot \frac{10 - D}{9}$$
    $$D' = \text{clamp}\left(w_7 \cdot D_0(4) + (1 - w_7) \cdot (D + \text{Damping}(\Delta D, D)), 1, 10\right)$$
    *(Features linear damping towards boundaries and mean reversion to the easy anchor $D_0(4)$).*

4.  **Recall Stability ($G \ge 2$):**
    $$S'_r = S \cdot \left(1 + e^{w_8} \cdot (11 - D) \cdot S^{-w_9} \cdot \left(e^{(1 - R) \cdot w_{10}} - 1\right) \cdot \text{penalty} \cdot \text{bonus}\right)$$
    *   $\text{penalty} = w_{15}$ if $G = 2$ ($\text{Hard}$), else $1.0$.
    *   $\text{bonus} = w_{16}$ if $G = 4$ ($\text{Easy}$), else $1.0$.

5.  **Lapse Stability ($G = 1$, $\text{Again}$):**
    $$S'_f = w_{11} \cdot D^{-w_{12}} \cdot \left((S + 1)^{w_{13}} - 1\right) \cdot e^{(1 - R) \cdot w_{14}}$$
    *   When short-term reviews are enabled, an additional post-lapse clamp floor applies:
        $$\text{floor} = \frac{S}{e^{w_{17} \cdot w_{18}}}$$
        $$S' = \text{clamp}(\text{floor}, S_{\min}, S'_f)$$

6.  **Short-term (Same-Day) Reviews ($t = 0$):**
    $$S_{\text{inc}} = S^{-0.01} \cdot e^{w_{17} \cdot (G - 3 + w_{18})}$$
    *   If $G \ge 2$, $S_{\text{inc}} = \max(S_{\text{inc}}, 1.0)$ so same-day reviews never degrade stability.
    *   $S' = \text{clamp}(S \cdot S_{\text{inc}}, S_{\min}, S_{\max})$.

### 3.3 Learning State Machine (`Scheduler`)

The scheduler wraps the FSRS memory transitions into a concrete state machine managing 4 states:
*   `ReviewState.new_`: Unreviewed card.
*   `ReviewState.learning`: Card undergoing sub-day acquisition steps (e.g., 1 min, 10 min).
*   `ReviewState.review`: Card graduated to day-scale FSRS scheduling.
*   `ReviewState.relearning`: Card that lapsed from `review` and is re-completing sub-day steps before re-graduating.

```
       [New Card]
           │
           ├──────────────────────────┐
      rating == Easy             rating < Easy
           │                          │
           ▼                          ▼
      [Graduated]               [Learning Steps]
    (Review State) ◄──────────── (Step 0 → Step 1)
           │      All steps passed
           │
      rating == Again (Lapse)
           │
           ▼
     [Relearning Steps] ────────► [Graduated]
                         Passed
```

### 3.4 Day Rollover & Cutoff Hour

To avoid penalizing late-night study sessions, `Scheduler.dayIndex` offsets local timestamps by a configurable cutoff hour (default `4:00 AM`). A review conducted at 2:00 AM is attributed to the preceding calendar day.

---

## 4. Session Construction & Queue Algorithms

Sessions are constructed cleanly without querying the database in loops:

1.  **Two-Hop Due Card Query:**
    `CardDao.dueCards` joins `schedule_states` $\to$ `cards` $\to$ `themes` in a single SQL query (the course is resolved through `themes.courseId`) filtering by `due <= now`.
2.  **Daily New-Card Intake Cap:**
    The new-card limit is strictly per day, not per session. The engine queries `ReviewLogs` to calculate `countNewCardsIntroducedToday` and subtracts this from `newCardsPerDay`.
3.  **Sequencing Order (`DueQueue`):**
    *   **New cards lead:** Introduced at the beginning of a session while student focus is fresh.
    *   **Blocked Practice (`InterleaveMode.blocked`):** Groups reviews by course, then theme. Suited for beginners learning rules.
    *   **Interleaved Practice (`InterleaveMode.interleaved`):** Round-robins cards across themes (Theme A $\to$ Theme B $\to$ Theme C). The resulting contextual contrast forces the brain to retrieve discriminative criteria.
4.  **Multi-Course Global Session:**
    `GlobalSessionBuilder` aggregates reviews across all active courses, keeping individual course blocks contiguous while respecting each course's interleaving policy and capping intake with an overarching global daily ceiling.

---

## 5. Cognitive Science Mechanics & The "Anti-Fluency" Stance

Flashcards2 embeds evidence-based learning principles directly into code:

### 5.1 Forced Generation Barrier
*   Passive review ("flip and look") causes learners to overestimate their competence.
*   In `ReviewScreen`, the reveal control is locked until the learner inputs an active attempt: either typing their recall in a text box or explicitly toggling an "I answered aloud" checkbox.
*   Attempt metadata (`durationMs`, `barrierCompleted`) is recorded in `ReviewLog` for calibration telemetry, but **never modifies the grade**. Self-evaluation remains sovereign.

### 5.2 Onboarding Cognitive Probes (`lib/domain/onboarding/`)
1.  **Working Memory Span (`memory_span.dart`):**
    An adaptive digit-span task tests sequential memory capacity ($4 \pm 1$ items). This sets the global default for daily card intake and informs card chunking limits.
2.  **Metacognitive Calibration (`calibration.dart`):**
    The user predicts their performance before taking memory tests. Learners identified as overconfident have the **Forced Generation Barrier enabled by default**.
3.  **Prior Knowledge Probe (`prior_knowledge.dart`):**
    Based on the *expertise-reversal effect*, novices require blocked practice to form schema, while proficient learners require interleaving to build discrimination.

---

## 6. Persistence & Data Layer (`lib/data/`)

Built on **Drift** over SQLite with `PRAGMA foreign_keys = ON`:

### 6.1 Database Schema & Tables
*   `Courses`: Metadata, intake limit, `interleave_mode` (`textEnum`), `archived` flag.
*   `Themes`: Categorical group under a course with cascade delete.
*   `Cards`: `front` and `back` text (Markdown + LaTeX), `source` (`manual` | `ai_generated`).
*   `CardImages`: Filesystem paths only. **No image BLOBs are stored in SQLite**, preventing database bloat.
*   `ScheduleStates`: 1-to-1 table linked to `Cards`. Stores $S, D$, `due`, `step`, and `state`.
*   `ReviewLogs`: **Append-only** table logging every review rating, latency, and scheduled interval. Never mutated.
*   `AppSettings`: Single-row table enforced by `CHECK (id = 1)`.

### 6.2 Schema Versioning & Migrations
*   **v1:** Initial schema. Hand-written `ReviewStateConverter` maps Dart keyword `new_` to SQL string `'new'`.
*   **v2:** Adds `step` column to `schedule_states` for sub-day interval tracking.
*   **v3:** Adds `memory_span` and `forced_generation_barrier` to `app_settings`.
*   Validated via schema dumps (`drift_schemas/`) and automated test suites (`schema_test.dart`).

### 6.3 Backup & Export (`lib/domain/backup/`)
*   Local JSON import/export with schema versioning (`magic: "flashcards2-backup"`).
*   **Zero Leakage Guarantee:** API keys, base URLs, and keystore secrets are strictly stripped via field-level allowlists.
*   **All-or-Nothing Validation:** Damaged or corrupt files are rejected prior to touching the database.

---

## 7. AI Content Pipeline: Image to Flashcards

Allows extracting atomic flashcards from textbook photos or notes:

```
[Pick/Capture Image] ──► [Downscale 1600px] ──► [Base64 Encode]
                                                        │
                                                        ▼
[User Edits/Approves] ◄── [Latex Escape Repair] ◄── [POST /chat/completions]
        │                     (Pre-JSON decoding)
        ▼
[Write to SQLite] (source: ai_generated)
```

### 7.1 Security & Authentication
*   Keys reside solely in `flutter_secure_storage` (Android Keystore).
*   **Provider Verification Trap:** Probing connection validity via `GET /models` was found to return `200 OK` publicly on some providers (e.g., Synthetic) even with garbage keys. Flashcards2 verifies keys by executing a dummy authenticated `POST /chat/completions` request.

### 7.2 Robust JSON Parsing & LaTeX Escape Repair
LLMs frequently return unescaped LaTeX backslashes inside JSON string literals. Standard JSON decoders will:
1.  Silently corrupt `\frac` into form-feed (`\f`) followed by `"rac"`.
2.  Corrupt `\beta` into backspace (`\b`) followed by `"eta"`.
3.  Crash on unescaped commands like `\int` or `\sqrt` (invalid escape sequences).

`FlashcardPrompt._repairLatexEscapes` inspects the text prior to JSON decoding:
*   Always repairs `\b` and `\f` to `\\b` and `\\f`.
*   Detects math boundaries (`$...$`) to distinguish prose newlines (`\n`) from math symbols (`\nu`).
*   Repairs all non-standard escapes while strictly preserving valid JSON controls (`\"`, `\\`, `\/`, `\uXXXX`).

---

## 8. Areas of Nuance, Uncertainties & Items for Deeper Investigation

> [!NOTE]
> Below are technical areas and architectural tradeoffs that have specific nuances or warrant deeper investigation.

### 8.1 FSRS-6 Migration — RESOLVED (2026-10-17)
*   **Status in Code:** Flashcards2 now schedules with **FSRS-6** via `package:fsrs` v2.0.1 (pinned exactly), consumed through the `Fsrs6SchedulerAdapter` anti-corruption layer and the `MemoryEngine` contract. The bespoke pure-Dart FSRS-5 port ($w_0 \dots w_{18}$) is frozen in-tree as the verified rollback engine and its own reference-vector test still gates it.
*   **Vector divergence — explained:** the interval-history divergence (`[0, 4, 14, 44, 125, 328...]` vs `[0, 4, 14, 45, 135, 372, 0, 0, 2, 5, 10, 20, 40]`) is the FSRS-6 curve itself: the trainable decay ($w_{20}$), same-day saturation ($w_{19}$), and deliberately more conservative post-lapse recovery. Verified empirically by the Phase 1 spike and pinned weights-to-source against py-fsrs v6.1.0 (commit `e64e3b4f710ada3486bca0e49b54ba33a3137654`).
*   **Accepted package divergence:** dart-fsrs 2.0.1 clamps same-day stability to ≥ 1 for `good`/`easy` only, so a same-day `hard` may decrease stability — unlike py-fsrs/fsrs-rs and unlike the frozen FSRS-5 port. Accepted as-is (plan Phase 2 decision 4).
*   **Short-Term Saturation Factor ($S^{-0.01}$):** applies only to the **frozen FSRS-5** engine: its specification documents omit this term in prose, yet reference implementations require it to reproduce test vectors; empirically verified and locked in `fsrs5.dart`. Under FSRS-6 the trainable $w_{19}$ slot governs same-day behavior instead.

### 8.2 85% Target Accuracy Band (`AccuracyHeuristic`)
*   *Need for investigation:* The theoretical paper (`the_science_of_learning.md`) mentions that an ~85% success rate is optimal for learning, but provides no mathematical transfer function to FSRS interval adjustments.
*   *Current Implementation:* Handled as an advisory heuristic with hysteresis ($>95\%$ widens, $<75\%$ tightens new-card intake). It does **not** mutate FSRS weights or raw intervals directly, ensuring stability calculations remain uncorrupted.

### 8.3 Heterogeneous LLM Provider Compatibility
*   While tested against Synthetic and DeepSeek, different OpenAI-compatible proxies handle vision payloads, system instructions, and schema enforcement (`response_format: { type: "json_object" }`) differently. DeepSeek, for instance, does not advertise `structured_outputs`. The custom pre-parsing pipeline mitigates this, but third-party providers with non-standard JSON streaming or prompt restrictions need per-provider monitoring.

### 8.4 LaTeX Test Font Substitution in Headless Environments
*   In automated headless unit/golden tests, Flutter substitutes the `Ahem` font. While layout boundaries, error badges, and theme contrast are verified in `latex_golden_test.dart`, actual visual glyph shapes of `flutter_math_fork` can only be visually validated on a physical Android display or emulator.

### 8.5 Deferred Feature Interfaces
*   Plain-text Markdown deck importer (planned in T2.5) and global card search (planned in T5.7) have supporting entity methods (`toPlainText`) but lack exposed presentation UI flows in the current build.
