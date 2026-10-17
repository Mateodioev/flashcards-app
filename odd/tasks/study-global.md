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
- L5: RDD assess on `064035c..HEAD`: risk `medium`, `review_due=false` (`under_budget`). User then explicitly requested the native review; consented `granted`.
- L6: Native review `review-6af485a3d3e6a3e5` (lens `review-reliability`): one CRITICAL finding (R3-nonarchived: archived exclusion unenforced). Bounded correction applied (`ede9bf1`, explicit `!course.archived` filter + archived-exclusion test); targeted validator passed; review **approved**, acknowledged, authority burned (`gentle-ai.review-acknowledged/v1`, consumed revision `f8142238…`).
- L7: Advisory (non-blocking) findings from the review, to treat as separate later work:
  - R3-dedup-cap (reliability): the due/fresh dedup set is built from `cappedReviews` (post `maxReviewCards`), so a card in both populations that falls beyond the 200-review cap can be emitted again as a new card.
  - R3-daily-ceiling (reliability): the global new-card ceiling is per-session and does not subtract new cards already introduced today, so the "daily" semantics of the global bound are unenforced.
  - R3-stale-invalidate (reliability): `startGlobalStudySession` never invalidates any provider after the session, unlike the theme path.
  - R3-counter-test (reliability): the aggregate-counter test only seeds one introduction per course, leaving multi-introduction accumulation unproved.
