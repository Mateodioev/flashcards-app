/// Shared canonical FSRS interval-history gates.
///
/// One source of truth for the canonical vector asserted by the adapter,
/// the domain interval-history gate, and the cutoff gate: the same
/// `G x6, A x2, G x5` ratings sequence producing the FSRS-6 day intervals
/// `[0, 4, 14, 45, 135, 372, 0, 0, 2, 5, 10, 20, 40]`. Centralized per the
/// native review advisory `R2-duplicated-canonical-vector` so a future
/// provenance pass (docs/fsrs6_migration_plan.md, Phase 4) re-derives the
/// vector in exactly one place.
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
