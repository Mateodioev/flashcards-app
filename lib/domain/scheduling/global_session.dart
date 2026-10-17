import 'dart:math' as math;

import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/domain/scheduling/due_queue.dart';
import 'package:flashcards2/domain/scheduling/session.dart';

/// One course's intake and ordering policy inside a global session.
class CourseStudyPolicy {
  const new({
    required this.courseId,
    required this.interleaveMode,
    required this.newCardsPerDay,
    this.newCardsAlreadyToday = 0,
  });

  final int courseId;
  final InterleaveMode interleaveMode;

  /// The course's per-day intake cap.
  final int newCardsPerDay;

  /// How many new cards this course has already introduced today.
  final int newCardsAlreadyToday;

  /// Cards this course may still introduce today, never negative.
  int get remainingNew => math.max(0, newCardsPerDay - newCardsAlreadyToday);
}

/// What a global session needs to know, across all its courses.
class GlobalSessionRequest {
  const new({
    required this.policies,
    this.maxReviewCards = 200,
    this.globalNewCardCeiling,
  });

  /// One policy per course. Courses absent here are excluded from the session.
  final List<CourseStudyPolicy> policies;

  /// A ceiling on the review portion, so a backlog cannot produce an endless
  /// session.
  final int maxReviewCards;

  /// An overall cap on new cards, applied across every course. When null the
  /// per-course allowances are the only limit.
  final int? globalNewCardCeiling;
}

/// Composes a session across many courses.
///
/// Course blocks stay contiguous — interleaving across unrelated courses is not
/// discriminative contrast, and the expertise-reversal evidence keeps novices
/// blocked — but *inside* each block the course's own [InterleaveMode] is
/// honoured. Reviews lead the session (a global queue must clear its backlog),
/// then new cards follow, each course drawing from its own remaining allowance
/// under the global ceiling.
abstract final class GlobalSessionBuilder {
  static ReviewSession build({
    required GlobalSessionRequest request,
    required List<DueEntry> due,
    required List<DueEntry> fresh,
  }) {
    final policies = {
      for (final policy in request.policies) policy.courseId: policy,
    };

    // --- Reviews: group by course, order each block by its own mode. ---
    final dueByCourse = <int, List<DueEntry>>{};
    for (final entry in due) {
      if (!policies.containsKey(entry.courseId)) continue;
      dueByCourse.putIfAbsent(entry.courseId, () => <DueEntry>[]).add(entry);
    }

    final reviewItems = <SessionItem>[];
    final courseIds = dueByCourse.keys.toList()..sort();
    for (final courseId in courseIds) {
      final ordered = orderDueCards(
        dueByCourse[courseId]!,
        mode: policies[courseId]!.interleaveMode,
      );
      reviewItems.addAll(
        ordered.map((entry) => SessionItem(entry: entry, isNew: false)),
      );
    }

    final cappedReviews = reviewItems.take(request.maxReviewCards).toList();
    final reviewedIds = cappedReviews.map((item) => item.cardId).toSet();

    // --- New cards: per-course allowance, then the global ceiling. ---
    final freshByCourse = <int, List<DueEntry>>{};
    for (final entry in fresh) {
      if (!policies.containsKey(entry.courseId)) continue;
      if (reviewedIds.contains(entry.cardId)) continue;
      freshByCourse.putIfAbsent(entry.courseId, () => <DueEntry>[]).add(entry);
    }
    for (final list in freshByCourse.values) {
      list.sort((a, b) => a.cardId.compareTo(b.cardId));
    }

    final newItems = <SessionItem>[];
    var remainingGlobal = request.globalNewCardCeiling;
    final freshCourseIds = freshByCourse.keys.toList()..sort();
    for (final courseId in freshCourseIds) {
      final allowance = policies[courseId]!.remainingNew;
      var taken = 0;
      for (final entry in freshByCourse[courseId]!) {
        if (taken >= allowance) break;
        if (remainingGlobal != null && remainingGlobal <= 0) break;
        newItems.add(SessionItem(entry: entry, isNew: true));
        taken++;
        if (remainingGlobal != null) remainingGlobal = remainingGlobal - 1;
      }
      if (remainingGlobal != null && remainingGlobal <= 0) break;
    }

    return ReviewSession(
      items: <SessionItem>[...cappedReviews, ...newItems],
      newCount: newItems.length,
    );
  }
}
