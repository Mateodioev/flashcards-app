# Card search (T5.7)

Branch: `feat/card-search` · Delivery strategy: `single-pr` · Test runner: `flutter test`

Global search/filter across cards, per `docs/plan.md` T5.7: "Search/filter across cards." Plan note: "`toPlainText` already exists for indexing, but nothing consumes it yet."

## Specs

- S1: A search entry exists on `CourseListScreen` (app-bar search action) and opens a search screen spanning all non-archived courses.
- S2: Matching is case-insensitive substring over `toPlainText(front)` + `toPlainText(back)` (LaTeX searched as its source, `$` delimiters never break a phrase match); the query is whitespace-trimmed; a blank query returns no results, never "all cards".
- S3: Optional cascading scope filters — course, then theme; default is all non-archived courses.
- S4: Results are deterministically ordered (`courseId`, `themeId`, `cardId`), each row labelled with its Course › Theme context and rendered through `CardContent` (LaTeX visible, consistent with T5.6); tapping a result opens the card editor.
- S5: Archived courses are excluded; no pagination in v1 (personal flashcard scale).

## Tasks

- [x] T1 (S2,S5) `findCardsWithContext` + `CardDao.cardsInScope` + `cardsMatchingQuery` + tests — route: inline — commit `1f62b65`.
- [x] T2 (S3,S4) `CardSearchScreen` + `cardSearchResults` provider + cascading scope chips — route: inline — commit `11887d1`.
- [x] T3 (S1) `CourseListScreen` app-bar search action — route: inline — commit `11887d1`.
- [x] T4 (S1-S5) Presentation tests — route: inline — commits `1f62b65`, `11887d1`.
- [x] T5 (S1-S5) `docs/plan.md` updated — route: inline — commit `11887d1`.

## Log

- L1: "Plan the global card search functionality (T5.7)"
- L2: Pending approval. Proposed decisions: D1 entries on `CourseListScreen` (mirrors global Study precedent); D2 Dart-side matching over the `toPlainText` projection instead of SQL LIKE (Unicode-aware case folding; phrases spanning a math span still match; honours the plan's indexing note); D3 cascading course/theme scope filters; D4 deterministic order + Course › Theme context; D5 archived excluded, no pagination.
- L3 (approved): "Approve, implement it". Decisions D1-D5 stand.
- L4: Naming deviation from L2: the interface method is `findCardsWithContext` (candidate fetch; matching is separate in `cardsMatchingQuery`), layering-respecting: data must not import the presentation-owned `toPlainText`. RED → GREEN observed for matcher, repository and screen tests.
- L5: Verified: `dart analyze` clean; `flutter test` 314 passed, 4 skipped. Work-unit commits `1f62b65` (data + matcher), `11887d1` (screen + entry + docs).
- L6: RDD assess `407b796..HEAD`: risk `medium`, `review_due=false` (`under_budget`, 1030 changed lines). No native review due; the reviewed boundary stays at `407b796` for the next feature. First run refused on undeclared untracked files; resolved by committing this document.
