# Design: Local-First Flashcards (Android, Dart/Flutter)

A single-user, offline-first flashcard app for Android. No accounts, no server, no
telemetry. The scheduler is a port of FSRS-5, not a naive interval ladder, and the
review interaction is built to defeat the fluency illusion rather than flatter it.

Source of truth for the learning science: [`../the_science_of_learning.md`](../the_science_of_learning.md).

## Core decisions (locked)

| Area | Decision | Consequence |
|---|---|---|
| Stack | Flutter / Dart | One language for scheduler, data, UI |
| Persistence | SQLite via Drift | Local-first, typed queries, real migrations |
| State | Riverpod | Testable, no `BuildContext` coupling |
| Backend | None | Local-first requires no server; no login means no accounts |
| Scheduler | **Native FSRS-5 port** | Highest-leverage component; must be unit-tested |
| Platforms | **Android only** | No iOS/web/desktop build surface |
| AI grading | **Disabled** | Self-grade + behavioral signals only; no model in the grading loop |
| LaTeX | `flutter_math_fork` | Pure Dart, offline, no WebView |
| Secrets | `flutter_secure_storage` | Android Keystore; never in SQLite, logs, or exports |
| Theme | Material 3, light/dark/system | Persisted user override |

### Rejected approaches

- **`flutter_tex` for LaTeX.** Requires a WebView plus bundled JS. For an offline-first
  app rendering many formulas per session, a WebView per formula is a performance and
  correctness liability. `flutter_math_fork` renders TeX natively.
- **SM-2-style scheduling.** Cheaper to write, but produces the "digital file cabinet"
  behavior criticized at `the_science_of_learning.md:1068`.
- **Cloud sync / accounts.** Out of scope by requirement.
- **AI grading of answers.** Rejected by product decision. It also imports a second
  source of truth into the student model; see *Grading* below.

## Architecture

Three layers, dependencies pointing inward.

```
presentation/   Flutter widgets + Riverpod providers
domain/         Entities, repository interfaces, Scheduler (pure Dart)
data/           Drift tables, DAOs, repository implementations
core/           Theme, DI wiring, error types, result types
```

`domain/` must not import Flutter. This is what makes the FSRS port unit-testable
without a widget harness — the single most important testability constraint here.

## Data model

```
Course ──< Theme ──< Card
                     ├── front / back  (markdown + inline $LaTeX$)
                     ├── images[]      (local file refs, not blobs in SQLite)
                     ├── source        (manual | ai_generated)
                     └── ScheduleState (owned by the scheduler)
Card ──< ReviewLog  (append-only)
```

`ReviewLog` is **append-only**. It is the only input any future FSRS weight
optimization may read. Review history is never mutated to correct statistics.

Image bytes live on the filesystem; SQLite stores paths. This keeps the database
small and makes backup/export tractable.

## Scheduler: native FSRS-5 port

FSRS-5 carries 19 parameters (`w0..w18`). The port consists of these components:

- Initial stability from the first grade.
- Initial difficulty from the first grade, clamped to the `[1, 10]` range.
- Difficulty update with mean reversion toward the initial-difficulty anchor.
- Retrievability as a power forgetting curve. FSRS-4.5/5 use
  `R(t, S) = (1 + F·t/S)^(−D)` with `F = 19/81` and `D = 0.5`;
  **confirm both constants against the canonical implementation before implementing.**
- Stability increase after a successful recall.
- Stability after a lapse.
- Same-day (short-term) stability update, which is the FSRS-5 addition over FSRS-4.5.

**Implementation rule:** port from the canonical reference implementation and validate
against its published reference vectors. Do **not** reconstruct the update equations
from the source treatise — they are not stated there (see *Known gaps* below).

Source document contradiction to resolve explicitly: `:721` gives Ebbinghaus
exponential decay `R(t) = e^(−t/S)`, while `:781` gives the FSRS power curve. These are
different models and stability does not mean the same thing in each. **This design uses
the power curve**, consistently, everywhere.

### Target accuracy band

The document asserts a ~85% optimal error rate (`:877-884`) and claims the scheduler
will "automatically tune to 85%" (`:1159`, `:1179`) — but supplies no mechanism, and the
85% result is empirically about *classification* error rates, not flashcard recall.
The document is hand-wavy here and the design must not pretend otherwise.

Implemented as an honest heuristic with hysteresis, clearly labelled in code:

- Rolling accuracy above ~95% over a window → widen intervals.
- Rolling accuracy below ~75% → tighten intervals and reduce new-card intake.
- Between the two → leave the scheduler alone.

This is a tuning layer over FSRS, not a reimplementation of it, and it is described as
a heuristic wherever it is surfaced to the user.

## Grading and the anti-fluency stance

The document is explicit that self-reported knowing is an unreliable signal, because the
fluency heuristic inflates judgements of learning (`:643-667`), and that passive
recognition mechanics must be eliminated (`:1095`).

Grading design:

- Primary mode is **generative recall**, not recognition. Multiple choice is not the
  default review mode (supports `:708-713`).
- **Forced Generation Barrier**: the reveal control is disabled until the learner has
  produced an attempt (free text, sketch, or voice), configurable per user
  (supports `:1155-1156`).
- The self-grade stands as the grade. Behavioral signals — latency, hint use, barrier
  completion — are recorded for **calibration warnings only**. They never silently
  override a grade, because a model-inferred override would create a second, invisible
  source of truth in the student model.

## Initial test

The source document contains two mutually inconsistent onboarding models: a 5–7 minute
audit (`:1100-1112`) and a 7-day audit (`:1044-1047`). It also concedes that the short
audit never measures prior knowledge or forgetting rate (`:1102-1112`), even though both
drive its decision matrix. This design takes the short audit and fixes the gap.

One short calibration session, three parts:

1. **Working-memory span** — sets the global default for new cards per day and how much
   content a single card may hold (Cowan's 4±1 cap, `:536-539`).
2. **Metacognitive calibration** — predict then perform. Measures the user's own
   fluency illusion. Overconfident ⇒ the Forced Generation Barrier defaults to on.
3. **Prior-knowledge probe per course** — routes each course to **blocked** (novice) or
   **interleaved** (expert) practice, per the expertise-reversal effect (`:992-1016`).

Resolution of the document's gap: the working-memory result sets a **global** default,
while the prior-knowledge probe sets a **per-course** policy. That is why each course
carries its own `newCardsPerDay` and `interleaveMode` even though onboarding runs once.

No learning-style questions. The document demolishes the VAK neuromyth (`:932-958`);
presentation mode is chosen by content type, never by self-reported learner type.

## Content pipeline: image → flashcards

The riskiest feature, ordered last for that reason. Every step has a failure mode:
network, auth, image encoding, prompt design, nondeterminism, malformed output.

1. Feature stays **disabled** until an API base URL and key are configured and verified.
2. The user **selects the course first** — enforced in the UI flow, not merely defaulted.
3. `GET /models` lists available models; vision-capable models are marked from
   `input_modalities`.
4. Image is picked and downscaled, then base64-encoded.
5. `POST /chat/completions` with a prompt demanding **strict JSON**. All models on the
   target provider advertise `structured_outputs`, so this is a supported request, not
   a hope.
6. A **mandatory review screen** lets the user edit, merge, or reject each generated
   card before it is persisted.
7. Only approved cards are written, tagged `source: ai_generated`.

Step 6 is non-negotiable. Auto-committing model output into a spaced-repetition deck is
how flashcard collections rot, and it also violates the atomicity requirement implied by
`:536-539`.

## AI integration contract

Verified against the live provider, not from documentation prose:

| Item | Value |
|---|---|
| Base URL (OpenAI-compatible) | `https://api.synthetic.new/openai/v1` |
| Auth | `Authorization: Bearer <key>` — **confirm at integration** |
| List models | `GET /models` |
| Generate | `POST /chat/completions` |
| Catalog size (observed) | 13 models |
| Vision-capable (observed) | 8 of 13 expose `"image"` in `input_modalities` |
| Structured output (observed) | 13 of 13 advertise `json_mode` + `structured_outputs` |

The model picker is generic: it reads `input_modalities` and `supported_features` rather
than hardcoding model names, so the app keeps working as the catalog changes.

Errors that must be handled explicitly: `401` invalid key, timeouts, non-JSON bodies,
JSON that parses but has the wrong shape, and partial card lists.

## Security and privacy

- API key only in `flutter_secure_storage` (Android Keystore).
- The key and image payloads are never logged, never included in exports, and never
  written to the database.
- No analytics, no crash reporting that ships content off-device.
- Export/backup is a local file. There is no cloud path.

## Theming

Material 3 with a seed color. `ThemeMode` (light / dark / system) is persisted in
`app_settings` and applied at the app root. Every screen must be audited in both modes —
LaTeX on dark backgrounds is a specific contrast risk and needs golden tests.

## Explicit non-goals

- No accounts, login, or sync.
- No cloud analytics or telemetry.
- No highlighting, summarization, or re-reading features — the meta-analysis rates all of
  them LOW (`:899-903`).
- No learning-style personalization.
- No iOS, web, or desktop targets.
- No AI grading.
- No features built on LOW-utility techniques from `:899-903`.

## Known gaps in the source document (and how this design handles them)

| Gap | Source | Handling |
|---|---|---|
| FSRS update equation and constants absent | `:781-788` | Port canonical FSRS-5; validate against reference vectors |
| Exponential vs power decay conflict | `:721` vs `:781` | Use power curve only |
| 85% rule has no scheduling mechanism | `:1159`, `:1179` | Hysteresis band, labelled a heuristic |
| Onboarding measures neither prior knowledge nor forgetting rate | `:1102-1112` | Per-course prior-knowledge probe added |
| Two conflicting onboarding models | `:1101` vs `:1044-1047` | Adopt the short audit |
| Dual-coding endorsed but imagery rated LOW | `:865` vs `:902` | Build image support for *captured content*, do not market it as a learning-style feature |

## Delivery decision

**No git remote. Local-only.** Confirmed by the project owner; this is a deliberate choice,
not an oversight.

Consequence for the ~4,200 forecast authored lines: pull requests are impossible, so
`chained-pr` and PR-based review slicing are inapplicable. Delivery is a sequence of local
work-unit commits on a feature branch. If a remote is added later, the forecast already
exceeds the ~400-line review budget, so a chain strategy becomes required at that point.
