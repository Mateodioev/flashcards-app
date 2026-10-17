# Study por curso

Branch: `feat/course-study` · Delivery strategy: `single-pr` · Test runner: `flutter test`

Add a `Study` action on a course (`ThemeListScreen`) that studies every theme in that course, reusing the existing review engine (FSRS-5 unchanged). Applies two consistency corrections: a genuinely daily new-card cap and effective use of `dayCutoffHour` / `forcedGenerationBarrier`.

## Specs

- S1: A `Study` button exists on the course screen (`ThemeListScreen`) and opens one session spanning all of that course's themes.
- S2: The course session studies due cards and new cards from every theme, new cards first then reviews, `maxReviewCards` 200, deterministic, deduplicated — same composition rules as the current theme session (`SessionBuilder`).
- S3: The new-card allowance is genuinely daily: `newCardsAlreadyToday` counts cards whose first review occurred in the current scheduling day, honouring the configured `dayCutoffHour`, and is subtracted from the course's `newCardsPerDay`.
- S4: The course's `interleaveMode` is applied to the review portion (blocked groups by course/theme; interleaved round-robins themes).
- S5: `forcedGenerationBarrier` from settings governs the reveal barrier, and the session `Scheduler` uses the configured `dayCutoffHour`.
- S6: The existing theme `Study` button keeps working and now also honours S3 and S5 (shared launcher, no duplicated logic).
- S7: FSRS-5 equations, weights, intervals, rating vocabulary, and the session summary are unchanged.

## Tasks

- T1 (S3) Add `ReviewLogRepository.countNewCardsIntroducedToday` + Drift implementation and tests — route: inline.
- T2 (S2,S3,S5) Extract a shared study-session launcher from `CardListScreen` — route: inline.
- T3 (S6) Refactor theme `Study` to use the launcher — route: inline.
- T4 (S1,S4) Add course `Study` to `ThemeListScreen` — route: inline.
- T5 (S1-S6) Presentation tests — route: inline.
- T6 (S1-S6) Update `docs/plan.md` — route: inline.

## Log

- L1: "Implementa primero Study por curso, primero planea el cambio y dividelo en todo list para revisarlo y ver si necesita algunas correcciones"
- L2 (approved): "El plan es perfecto, continua. Si aplica las dos correcciones de consistencia"
- L3: Plan reviewed and approved; scope = course Study + the two consistency corrections; global all-courses Study deferred.
