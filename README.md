# Flashcards

> Offline-first, single-user spaced-repetition flashcards for Android — powered by a native FSRS-5 scheduler and built to defeat the fluency illusion.

No accounts, no server, no telemetry. Everything lives in a local SQLite database. The scheduling is a verified port of [FSRS-5](https://github.com/open-spaced-repetition/fsrs-rs), not a naive interval ladder, and the review flow is designed around the learning science in [`the_science_of_learning.md`](the_science_of_learning.md).

## Features

- **Study at three scopes** — a single theme, a whole course, or every course at once (global).
- **Native FSRS-5 scheduling** — `new → learning → review → relearning`, with sub-day learning steps and a configurable day cutoff (default 4:00 AM).
- **Daily intake control** — per-course new-card caps plus a global daily ceiling derived from your working-memory span.
- **Anti-fluency review** — a forced generation barrier (optional), self-grading (`Again / Hard / Good / Easy`), and an honest end-of-session summary.
- **Evidence-based sequencing** — blocked or interleaved practice per course, chosen by an onboarding prior-knowledge probe (expertise-reversal effect).
- **Rich cards** — Markdown with inline LaTeX, rendered offline via `flutter_math_fork` (no WebView).
- **Image → flashcards** — extract cards from a photo using any OpenAI-compatible vision model; the API key never leaves the Android Keystore.
- **Backup / export** — local JSON import/export that strips secrets and rejects corrupt files before touching the database.
- **Material 3** — light, dark, and system themes with a persisted override.

## Quick start

```bash
flutter pub get
flutter run
```

Requires Flutter with Dart SDK `^3.13.5`. The app targets **Android**.

## Development

```bash
# Static analysis (very_good_analysis at full strength)
dart analyze

# Full test suite
flutter test

# Regenerate Drift / Riverpod code after schema or provider changes
dart run build_runner build -d
```

## How studying works

Each card carries a two-dimensional memory state — **stability** (days for recall to fall to 90%) and **difficulty** (1–10). Every rating updates that state through the FSRS-5 equations, and the card is rescheduled into one of four states:

| State | Meaning |
|-------|---------|
| `new` | Never reviewed |
| `learning` | In sub-day acquisition steps (e.g. 1 min, 10 min) |
| `review` | Graduated to day-scale intervals |
| `relearning` | Lapsed from `review`, redoing steps before re-graduating |

Sessions are composed from two populations — cards **due** for review and cards **never reviewed** — and every review is written to an append-only log that a future FSRS weight-optimization pass can read.

## Architecture

Three layers, dependencies pointing inward:

```
lib/presentation/   Flutter widgets + Riverpod providers
lib/domain/         Entities, repository interfaces, FSRS-5, session engine (pure Dart)
lib/data/           Drift (SQLite) tables, DAOs, AI client, secure storage
lib/core/           Material 3 theme and app wiring
```

The domain layer has no Flutter or database imports, which is what keeps the scheduler and session logic deterministically unit-testable.

## Documentation

- [`docs/design.md`](docs/design.md) — locked architecture decisions and the FSRS-5 equations.
- [`docs/plan.md`](docs/plan.md) — build-order checklist with the rationale behind each task.
- [`the_science_of_learning.md`](the_science_of_learning.md) — the cognitive-science source of truth this app is built from.
