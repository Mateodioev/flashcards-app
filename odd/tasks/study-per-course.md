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

- [x] T1 (S3) `ReviewLogRepository.countNewCardsIntroducedToday` + Drift implementation and tests — route: inline — commit `68de3d0`.
- [x] T2 (S2,S3,S5) Shared study-session launcher extracted from `CardListScreen` — route: inline — commit `15074f2`.
- [x] T3 (S6) Theme `Study` refactored to use the launcher — route: inline — commit `15074f2`.
- [x] T4 (S1,S4) Course `Study` added to `ThemeListScreen` — route: inline — commit `15074f2`.
- [x] T5 (S1-S6) Presentation tests — route: inline — commit `15074f2`.
- [x] T6 (S1-S6) `docs/plan.md` updated — route: inline — commit `15074f2`.

## Log

- L1: "Implementa primero Study por curso, primero planea el cambio y dividelo en todo list para revisarlo y ver si necesita algunas correcciones"
- L2 (approved): "El plan es perfecto, continua. Si aplica las dos correcciones de consistencia"
- L3: Plan reviewed and approved; scope = course Study + the two consistency corrections; global all-courses Study deferred.
- L4: Verified: `dart analyze` clean; `flutter test` 278 passed, 4 skipped. Two work-unit commits: `68de3d0`, `15074f2`.
- L5: RDD assess on `9686cce..HEAD`: risk `medium`, `review_due=false` (`under_budget`). User then explicitly requested the native review; consented `granted`.
- L6: Native review `review-af2f5c84d30e7deb` (lens `review-reliability`): **approved**, acknowledged, authority burned (`gentle-ai.review-acknowledged/v1`, consumed revision `63880ce…`). Reviewed boundary advances past `7351e15`.
- L7: Advisory (non-blocking) findings from the review, to treat as separate later work:
  - R3-1 (reliability): `course_study_test.dart:145` seeds the "already introduced" log with wall-clock `DateTime.now()`, so the daily-allowance test can flake across the cutoff boundary.
  - R3-2 (reliability): theme `Study` now hard-blocks with "Course no longer exists." when `findById(theme.courseId)` is null, instead of the old graceful degradation.
  - R3-3 (reliability): no behavioral coverage for the theme-scoped path of `startStudySession` (themeId scoping, `ref.invalidate`, null-course branch) and the `themeId` parameter of `countNewCardsIntroducedToday`.
