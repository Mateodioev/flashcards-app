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

## Scheduler: FSRS-5 (verified)

**Verification status: COMPLETE.** The constants and equations below were taken from the
canonical reference implementations, not from `the_science_of_learning.md` (which supplies
neither — see *Known gaps*). Sources, read directly:

- `open-spaced-repetition/awesome-fsrs` wiki, *The Algorithm*
- `open-spaced-repetition/ts-fsrs` — `packages/fsrs/src/algorithm.ts`, `src/constant.ts`
- `open-spaced-repetition/fsrs-rs` — `src/inference.rs`
- Cross-checked against an independent engineering write-up of the same curve

Do not edit these values from memory. Re-verify against those sources if they must change.

### Constants

| Constant | Value | Note |
|---|---|---|
| `DECAY` | `-0.5` | FSRS-5 fixed decay. (FSRS-6 makes it trainable via `w20`.) |
| `FACTOR` | `0.9^(1/DECAY) − 1` = `19/81` ≈ `0.2345679012` | **computed, never hardcoded** |
| `S_MIN` / `S_MAX` | `0.001` / `36500.0` | stability clamp |
| `maximum_interval` | `36500` days | interval ceiling |
| `request_retention` | `0.9` | default target |
| fuzzing | **disabled** | determinism: required for reproducible tests |
| `enable_short_term` | **pinned explicitly** | see the trap below |

`FACTOR` is derived, not literal: `factor = exp((1/decay) · ln 0.9) − 1` where `decay` is
negative. It is defined so that `R(S, S) = 0.9` — an interval equal to stability means 90%
predicted recall, by construction. Writing `0.2346` as a literal decouples the two
constants and silently breaks that identity.

### Equations

Grades are 1-indexed: `1 = Again, 2 = Hard, 3 = Good, 4 = Easy`.
`R` in the stability formulas is the retrievability *at the time of review*.

```
Retrievability:      R(t, S) = (1 + FACTOR · t / S) ^ DECAY
Interval:            I(r, S) = (S / FACTOR) · (r ^ (1 / DECAY) − 1)
                     interval = clamp(round(S · intervalModifier), 1, maximum_interval)
Initial stability:   S0(G) = max(w[G−1], 0.1)
Initial difficulty:  D0(G) = w[4] − e^(w[5] · (G − 1)) + 1     # clamped to [1,10] at use site
Difficulty update:   delta_d = −w[6] · (G − 3)
                     linear_damping(delta_d, D) = delta_d · (10 − D) / 9
                     next_d = D + linear_damping(delta_d, D)
                     D' = clamp(w[7] · D0(4) + (1 − w[7]) · next_d, 1, 10)
Stability, recall:   S'r = S · (1 + e^w[8] · (11 − D) · S^(−w[9]) · (e^((1−R)·w[10]) − 1)
                                        · hard_penalty · easy_bound)
                     hard_penalty = w[15] if G == 2 else 1
                     easy_bound   = w[16] if G == 4 else 1
                     clamped to [S_MIN, S_MAX]
Stability, lapse:    S'f = w[11] · D^(−w[12]) · ((S + 1)^w[13] − 1) · e^((1−R)·w[14])
                     clamped to [S_MIN, S_MAX]
                     with short-term enabled, additionally:
                       next_s_min = S / e^(w[17] · w[18])
                       S' = clamp(next_s_min, S_MIN, S'f)
Short-term (t == 0): sinc = S^(−0.01) · e^(w[17] · (G − 3 + w[18]))
                     sinc = max(sinc, 1.0) when G >= 2
                     S' = clamp(S · sinc, S_MIN, S_MAX)
```

Dispatch order in the state transition, which the reference implementation gates in this
exact sequence — order matters:

1. `t < 0` → error. `G` outside `0..4` → error.
2. No prior memory state (`D == 0 && S == 0`) → initialise, clamped to `[1, 10]`.
3. `G == 0` → state unchanged (no grade recorded).
4. `t == 0 && enable_short_term` → short-term formula.
5. `G == 1` → lapse formula.
6. otherwise → recall formula.

### Default weights (19, `w0..w18`)

```
[0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575,
 0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621]
```

### Reference vectors — the acceptance gate for T3.2

A port is correct **only** if it reproduces these. Taken from the canonical FSRS-5 suite.

- **Interval history** — ratings `[G,G,G,G,G,G,A,A,G,G,G,G,G]`:
  `[0, 4, 14, 44, 125, 328, 0, 0, 6, 14, 31, 65, 130]`
- **First review of a new card**, all four grades in order:
  - stability `[0.40255, 1.18385, 3.173, 15.69105]`
  - difficulty `[7.1949, 6.48830527, 5.28243442, 3.22450159]`
  - scheduled days `[0, 0, 0, 16]`
  - states `[Learning, Learning, Learning, Review]`
- **Memory state** after `[A,G,G,G,G,G]` at intervals `[0,0,1,3,8,21]`:
  - short-term enabled: stability `48.27115294`, difficulty `7.10441712`
  - short-term disabled: stability `48.065163`, difficulty `7.10441712`

The difficulty vector also validates `D0(G)` independently: `D0(1) = w4 = 7.1949`,
`D0(3) = 5.2824…`, `D0(4) = 3.2245…` — all three match. `S0(G) = w[G−1]` matches directly.

### The `enable_short_term` trap (verified, not theoretical)

FSRS-5 as implemented by the reference suite carries a flag, defaulting to **enabled**,
that changes **two** distinct code paths:

1. same-day reviews use the short-term stability formula; and
2. a **lapse** is followed by an additional clamp: `next_s_min = S / e^(w17·w18)`,
   then `S' = clamp(next_s_min, S_MIN, S'f)`.

The effect is not cosmetic. The two memory-state vectors differ (48.27115294 vs 48.065163)
*purely* because of this flag, and it also changes the post-lapse clamp. The
interval-history vector above is produced with the flag at its reference default —
**enabled** — so the Dart port must pin it explicitly to that value, never leave it to an
implicit default, and the test suite must cover both branches. Leaving it unpinned is how a
"correct-looking" port silently diverges.

### The short-term saturation term (empirically established)

The short-term formula carries an `S^(−0.01)` factor. That `0.01` is **not** a
weight-vector entry — FSRS-5 has no `w19` slot — it is the parameter-clamp **floor** applied
to the short-term exponent whenever short-term reviews are enabled.

This was found by running the reference vectors, not by reading prose. Three candidate
forms were tested against the canonical memory-state vector `48.27115294`:

| Short-term form | Result | Error |
|---|---|---|
| `S · e^(w17·(G−3+w18))` (no saturation) | `48.26549258` | `5.7e-3` — fails |
| `S^(−0.0658)` (FSRS-6 default `w19`) | `48.30315946` | `3.2e-2` — fails |
| `S^(−0.01)` (clamp floor) | `48.27115127` | `1.7e-6` — **matches** |

Solving analytically for the exponent the vector implies gives `0.0100029`, which is the
clamp floor to within floating-point noise.

Both errors above are *plausible-looking numbers*. Neither throws, neither looks wrong in a
UI, and the first is within 0.012% of correct. This is exactly why the reference vectors —
not prose, and not inspection — are the acceptance gate for T3.2.

The `max(sinc, 1.0)` mask for `G >= 2` still applies: a same-day review must never *reduce*
stability for Hard, Good or Easy.

### Reference implementation: port or depend?

An official Dart package exists: `fsrs` **2.0.1** (`open-spaced-repetition/dart-fsrs`,
65 stars, not archived, 5 open issues, last pushed **2025-06-20**).

It is **not** a drop-in for this design:

- Its changelog says `2.0.0 → FSRS-6`. It bundles FSRS-6 default weights and does not
  contain the FSRS-5 vector `0.40255`.
- Its own interval-history test expects `[0, 4, 14, 45, 135, 372, 0, 0, 2, 5, 10, 20, 40]`,
  which **diverges** from the canonical FSRS-5 vector `[0, 4, 14, 44, 125, 328, 0, 0, 6, 14, 31, 65, 130]`
  from the 4th element onward. Whether that is the FSRS-6 curve or a divergence in its
  post-lapse handling was **not** established.

So: depending on it would mean adopting FSRS-6, not FSRS-5, and accepting unverified
vector behaviour. This is an open decision — see `plan.md`.

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
| FSRS update equation and constants absent | `:781-788` | **Resolved.** Constants and equations verified against the canonical reference implementations and written into this document. The treatise was never usable as a spec here. |
| Exponential vs power decay conflict | `:721` vs `:781` | Use power curve only (`DECAY = −0.5`). The treatise's exponential form is not FSRS. |
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
