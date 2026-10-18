/// Shared canonical FSRS interval-history gates.
///
/// Centralized per the native review advisory
/// `R2-duplicated-canonical-vector`.
///
/// PROVENANCE (docs/fsrs6_migration_plan.md, Phase 4):
/// - Weights: the original 21-parameter FSRS-6 defaults, exactly matching
///   `open-spaced-repetition/py-fsrs` **v6.1.0**, commit
///   `e64e3b4f710ada3486bca0e49b54ba33a3137654`
///   (`fsrs/scheduler.py`, `DEFAULT_PARAMETERS`, fetched 2026-10-17).
///   `package:fsrs` 2.0.1 (pub.dev sha256 `b50dbee45...`) embeds the same
///   vector element-for-element.
/// - Intervals: reproduced end-to-end from those weights by the dart-fsrs
///   scheduler in the executable Phase 1 spike — the tooling itself is the
///   derivation; the vector is NOT copied from prose.
/// - Upstream drift (known, accepted): py-fsrs v6.2.0+ and fsrs-rs moved
///   to re-optimized default weights (decay 0.1542), which would produce a
///   DIFFERENT interval vector. Any future weight upgrade re-derives the
///   vector here, in this one place.
library;

import 'package:flashcards2/domain/enums.dart';

/// The 13-review ratings sequence of the canonical interval-history gate.
const fsrs6CanonicalRatings = <Rating>[
  Rating.good, Rating.good, Rating.good, Rating.good, Rating.good,
  Rating.good, //
  Rating.again, Rating.again, //
  Rating.good, Rating.good, Rating.good, Rating.good, Rating.good,
];

/// FSRS-6 expected day intervals for [fsrs6CanonicalRatings].
const fsrs6CanonicalIntervals = <int>[
  0, 4, 14, 45, 135, 372, 0, 0, 2, 5, 10, 20, 40, //
];

/// FSRS-5 expected day intervals for [fsrs6CanonicalRatings], kept for the
/// frozen-rollback gate (the FSRS-5 and FSRS-6 sequences share the ratings).
const fsrs5CanonicalIntervals = <int>[
  0, 4, 14, 44, 125, 328, 0, 0, 6, 14, 31, 65, 130, //
];
