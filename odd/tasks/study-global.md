# Study global

Branch: `feat/study-global` · Delivery strategy: `single-pr` · Test runner: `flutter test`

Add a `Study` action on the main screen (`CourseListScreen`) that studies every non-archived course in one session, reusing the existing review engine (FSRS-5 unchanged). Policy is per course; a global daily new-card ceiling derived from the working-memory span bounds total intake. Reviews lead the session; new cards follow.

## Specs

- S1: A `Study` button exists on `CourseListScreen` and opens one session spanning all non-archived courses.
- S2: The session composes due cards from every course; each course's own `interleaveMode` is applied inside its block, and course blocks are concatenated in deterministic (ascending `courseId`) order.
- S3: Reviews lead the session; new cards follow, capped at `maxReviewCards = 200` for reviews.
- S4: New-card intake is per course (`newCardsPerDay − newCardsAlreadyToday`, never negative), deduplicated against reviews, and additionally capped by a global daily ceiling derived from `memorySpan` (fallback span when unmeasured).
- S5: `forcedGenerationBarrier` and the configured `dayCutoffHour` are applied to the session and its `Scheduler`.
- S6: FSRS-5 equations, weights, intervals, rating vocabulary, and the session summary are unchanged.

## Tasks

- [x] T1 (S4) `countNewCardsIntroducedTodayByCourse` + Drift aggregate query and tests — route: inline — commit `eb9673d`.
- [x] T2 (S2,S3,S4) `CourseStudyPolicy`, `GlobalSessionRequest`, `GlobalSessionBuilder` + tests — route: inline — commit `e5ca990`.
- [x] T3 (S1,S5) `startGlobalStudySession` + `CourseListScreen` Study button — route: inline — commit `e0c7990`.
- [x] T4 (S1-S5) Presentation tests — route: inline — commit `e0c7990`.
- [x] T5 (S1-S6) `docs/plan.md` updated — route: inline — commit `e0c7990`.

## Log

- L1: "Ahora planea el Study global y presentame el plan"
- L2 (approved): "Plan perfecto!, continua"
- L3: Decisions D1 (course-contiguous), D2 (reviews first), D3 (global ceiling from span), D4 (non-archived only), D5 (no ReviewLog migration) — approved.
- L4: Verified: `dart analyze` clean; `flutter test` 289 passed, 4 skipped. Work-unit commits: `eb9673d`, `e5ca990`, `e0c7990`.
