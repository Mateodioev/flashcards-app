// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The application database.
///
/// Overridden in `main` with the on-disk database, and in tests with an
/// in-memory one — so nothing below this line needs to know which it has.

@ProviderFor(database)
final databaseProvider = DatabaseProvider._();

/// The application database.
///
/// Overridden in `main` with the on-disk database, and in tests with an
/// in-memory one — so nothing below this line needs to know which it has.

final class DatabaseProvider
    extends $FunctionalProvider<AppDatabase, AppDatabase, AppDatabase>
    with $Provider<AppDatabase> {
  /// The application database.
  ///
  /// Overridden in `main` with the on-disk database, and in tests with an
  /// in-memory one — so nothing below this line needs to know which it has.
  DatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'databaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$databaseHash();

  @$internal
  @override
  $ProviderElement<AppDatabase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppDatabase create(Ref ref) {
    return database(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppDatabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppDatabase>(value),
    );
  }
}

String _$databaseHash() => r'ee2419548733077cb9a7fffbdc13165638694101';

@ProviderFor(courseRepository)
final courseRepositoryProvider = CourseRepositoryProvider._();

final class CourseRepositoryProvider
    extends
        $FunctionalProvider<
          CourseRepository,
          CourseRepository,
          CourseRepository
        >
    with $Provider<CourseRepository> {
  CourseRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'courseRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$courseRepositoryHash();

  @$internal
  @override
  $ProviderElement<CourseRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CourseRepository create(Ref ref) {
    return courseRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CourseRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CourseRepository>(value),
    );
  }
}

String _$courseRepositoryHash() => r'71ab20a6b501dcd7ed96fc676db3053df6bb1fa9';

@ProviderFor(cardRepository)
final cardRepositoryProvider = CardRepositoryProvider._();

final class CardRepositoryProvider
    extends $FunctionalProvider<CardRepository, CardRepository, CardRepository>
    with $Provider<CardRepository> {
  CardRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cardRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cardRepositoryHash();

  @$internal
  @override
  $ProviderElement<CardRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CardRepository create(Ref ref) {
    return cardRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CardRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CardRepository>(value),
    );
  }
}

String _$cardRepositoryHash() => r'6cbabb3d60504ceb157d5d00ba7f8b91ac86eec4';

@ProviderFor(reviewLogRepository)
final reviewLogRepositoryProvider = ReviewLogRepositoryProvider._();

final class ReviewLogRepositoryProvider
    extends
        $FunctionalProvider<
          ReviewLogRepository,
          ReviewLogRepository,
          ReviewLogRepository
        >
    with $Provider<ReviewLogRepository> {
  ReviewLogRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reviewLogRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reviewLogRepositoryHash();

  @$internal
  @override
  $ProviderElement<ReviewLogRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReviewLogRepository create(Ref ref) {
    return reviewLogRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReviewLogRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReviewLogRepository>(value),
    );
  }
}

String _$reviewLogRepositoryHash() =>
    r'd384fd94e05a66e93b7178176f35203608a8d58a';

@ProviderFor(settingsRepository)
final settingsRepositoryProvider = SettingsRepositoryProvider._();

final class SettingsRepositoryProvider
    extends
        $FunctionalProvider<
          SettingsRepository,
          SettingsRepository,
          SettingsRepository
        >
    with $Provider<SettingsRepository> {
  SettingsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsRepositoryHash();

  @$internal
  @override
  $ProviderElement<SettingsRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SettingsRepository create(Ref ref) {
    return settingsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SettingsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SettingsRepository>(value),
    );
  }
}

String _$settingsRepositoryHash() =>
    r'089b44970711e54ecd9e562ac7227c1206e39cf8';

@ProviderFor(reminderRepository)
final reminderRepositoryProvider = ReminderRepositoryProvider._();

final class ReminderRepositoryProvider
    extends
        $FunctionalProvider<
          ReminderRepository,
          ReminderRepository,
          ReminderRepository
        >
    with $Provider<ReminderRepository> {
  ReminderRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reminderRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reminderRepositoryHash();

  @$internal
  @override
  $ProviderElement<ReminderRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReminderRepository create(Ref ref) {
    return reminderRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReminderRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReminderRepository>(value),
    );
  }
}

String _$reminderRepositoryHash() =>
    r'f3b1ba9e0ec7a4019437dfb13de176323468baaf';

@ProviderFor(notificationGateway)
final notificationGatewayProvider = NotificationGatewayProvider._();

final class NotificationGatewayProvider
    extends
        $FunctionalProvider<
          NotificationGateway,
          NotificationGateway,
          NotificationGateway
        >
    with $Provider<NotificationGateway> {
  NotificationGatewayProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notificationGatewayProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notificationGatewayHash();

  @$internal
  @override
  $ProviderElement<NotificationGateway> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  NotificationGateway create(Ref ref) {
    return notificationGateway(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NotificationGateway value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NotificationGateway>(value),
    );
  }
}

String _$notificationGatewayHash() =>
    r'd8dc886357ae79dab5eecc3e2d4589b9976426bf';

/// Saves a reminder through the T5 permission flow, then reconciles (plan
/// §1: every subscription change reschedules). The result carries the final
/// access state so the UI can explain a denial or offer the settings
/// deep-link for a muted channel.

@ProviderFor(saveReminder)
final saveReminderProvider = SaveReminderProvider._();

/// Saves a reminder through the T5 permission flow, then reconciles (plan
/// §1: every subscription change reschedules). The result carries the final
/// access state so the UI can explain a denial or offer the settings
/// deep-link for a muted channel.

final class SaveReminderProvider
    extends
        $FunctionalProvider<
          Future<({ReminderAccess access, ReminderSubscription saved})>
          Function(ReminderSubscription draft),
          Future<({ReminderAccess access, ReminderSubscription saved})>
          Function(ReminderSubscription draft),
          Future<({ReminderAccess access, ReminderSubscription saved})>
          Function(ReminderSubscription draft)
        >
    with
        $Provider<
          Future<({ReminderAccess access, ReminderSubscription saved})>
          Function(ReminderSubscription draft)
        > {
  /// Saves a reminder through the T5 permission flow, then reconciles (plan
  /// §1: every subscription change reschedules). The result carries the final
  /// access state so the UI can explain a denial or offer the settings
  /// deep-link for a muted channel.
  SaveReminderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'saveReminderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$saveReminderHash();

  @$internal
  @override
  $ProviderElement<
    Future<({ReminderAccess access, ReminderSubscription saved})> Function(
      ReminderSubscription draft,
    )
  >
  $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  Future<({ReminderAccess access, ReminderSubscription saved})> Function(
    ReminderSubscription draft,
  )
  create(Ref ref) {
    return saveReminder(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    Future<({ReminderAccess access, ReminderSubscription saved})> Function(
      ReminderSubscription draft,
    )
    value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<
            Future<({ReminderAccess access, ReminderSubscription saved})>
            Function(ReminderSubscription draft)
          >(value),
    );
  }
}

String _$saveReminderHash() => r'c6ffa2f45230c678029e439c0d64ce3aa65457ef';

/// Deletes a reminder, then reconciles.

@ProviderFor(deleteReminder)
final deleteReminderProvider = DeleteReminderProvider._();

/// Deletes a reminder, then reconciles.

final class DeleteReminderProvider
    extends
        $FunctionalProvider<
          Future<void> Function(int id),
          Future<void> Function(int id),
          Future<void> Function(int id)
        >
    with $Provider<Future<void> Function(int id)> {
  /// Deletes a reminder, then reconciles.
  DeleteReminderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deleteReminderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deleteReminderHash();

  @$internal
  @override
  $ProviderElement<Future<void> Function(int id)> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Future<void> Function(int id) create(Ref ref) {
    return deleteReminder(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Future<void> Function(int id) value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Future<void> Function(int id)>(
        value,
      ),
    );
  }
}

String _$deleteReminderHash() => r'fcd4f2f300f193bfa39a75b3bdc666ae43a8bfab';

/// Cancels every scheduled reminder and reschedules from the database —
/// the canonical reconciliation rule (plan §1). The returned closure is how
/// every caller (app start, every subscription save/delete, restore after
/// backup) triggers the same code path; nothing tracks OS state piecewise.

@ProviderFor(reminderReschedule)
final reminderRescheduleProvider = ReminderRescheduleProvider._();

/// Cancels every scheduled reminder and reschedules from the database —
/// the canonical reconciliation rule (plan §1). The returned closure is how
/// every caller (app start, every subscription save/delete, restore after
/// backup) triggers the same code path; nothing tracks OS state piecewise.

final class ReminderRescheduleProvider
    extends
        $FunctionalProvider<
          Future<void> Function(),
          Future<void> Function(),
          Future<void> Function()
        >
    with $Provider<Future<void> Function()> {
  /// Cancels every scheduled reminder and reschedules from the database —
  /// the canonical reconciliation rule (plan §1). The returned closure is how
  /// every caller (app start, every subscription save/delete, restore after
  /// backup) triggers the same code path; nothing tracks OS state piecewise.
  ReminderRescheduleProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reminderRescheduleProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reminderRescheduleHash();

  @$internal
  @override
  $ProviderElement<Future<void> Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Future<void> Function() create(Ref ref) {
    return reminderReschedule(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Future<void> Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Future<void> Function()>(value),
    );
  }
}

String _$reminderRescheduleHash() =>
    r'27dbd8cbd979eced8d22a7238dfdc5afb17f0d0a';

/// Every reminder subscription, streamed from the repository (plan D4): the
/// reminder-settings screen (T6) rebuilds its rows whenever a save or delete
/// lands, instead of hand-maintaining a copy.

@ProviderFor(reminderSubscriptions)
final reminderSubscriptionsProvider = ReminderSubscriptionsProvider._();

/// Every reminder subscription, streamed from the repository (plan D4): the
/// reminder-settings screen (T6) rebuilds its rows whenever a save or delete
/// lands, instead of hand-maintaining a copy.

final class ReminderSubscriptionsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ReminderSubscription>>,
          List<ReminderSubscription>,
          Stream<List<ReminderSubscription>>
        >
    with
        $FutureModifier<List<ReminderSubscription>>,
        $StreamProvider<List<ReminderSubscription>> {
  /// Every reminder subscription, streamed from the repository (plan D4): the
  /// reminder-settings screen (T6) rebuilds its rows whenever a save or delete
  /// lands, instead of hand-maintaining a copy.
  ReminderSubscriptionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reminderSubscriptionsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reminderSubscriptionsHash();

  @$internal
  @override
  $StreamProviderElement<List<ReminderSubscription>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ReminderSubscription>> create(Ref ref) {
    return reminderSubscriptions(ref);
  }
}

String _$reminderSubscriptionsHash() =>
    r'63168aff0be21f06a32e6545c951b9e691eac697';

/// Current OS access state (T5/S10). Read-only: requesting the permission is
/// the save flow's job, this provider only decides whether the banner that
/// explains why reminders will not fire is visible.

@ProviderFor(reminderAccess)
final reminderAccessProvider = ReminderAccessProvider._();

/// Current OS access state (T5/S10). Read-only: requesting the permission is
/// the save flow's job, this provider only decides whether the banner that
/// explains why reminders will not fire is visible.

final class ReminderAccessProvider
    extends
        $FunctionalProvider<
          AsyncValue<ReminderAccess>,
          ReminderAccess,
          FutureOr<ReminderAccess>
        >
    with $FutureModifier<ReminderAccess>, $FutureProvider<ReminderAccess> {
  /// Current OS access state (T5/S10). Read-only: requesting the permission is
  /// the save flow's job, this provider only decides whether the banner that
  /// explains why reminders will not fire is visible.
  ReminderAccessProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reminderAccessProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reminderAccessHash();

  @$internal
  @override
  $FutureProviderElement<ReminderAccess> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ReminderAccess> create(Ref ref) {
    return reminderAccess(ref);
  }
}

String _$reminderAccessHash() => r'9236c95ea20eafc0c68d524ca36cb9d2f5a3009d';

@ProviderFor(reminderTargets)
final reminderTargetsProvider = ReminderTargetsProvider._();

final class ReminderTargetsProvider
    extends
        $FunctionalProvider<
          AsyncValue<ReminderTargets>,
          ReminderTargets,
          FutureOr<ReminderTargets>
        >
    with $FutureModifier<ReminderTargets>, $FutureProvider<ReminderTargets> {
  ReminderTargetsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reminderTargetsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reminderTargetsHash();

  @$internal
  @override
  $FutureProviderElement<ReminderTargets> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ReminderTargets> create(Ref ref) {
    return reminderTargets(ref);
  }
}

String _$reminderTargetsHash() => r'21dd44ac012e1843e120858ffb51bbd673a86d80';

/// Non-archived courses.
///
/// Invalidate after any create, edit or delete so the list rebuilds from the
/// database rather than from a hand-maintained cache.

@ProviderFor(courses)
final coursesProvider = CoursesProvider._();

/// Non-archived courses.
///
/// Invalidate after any create, edit or delete so the list rebuilds from the
/// database rather than from a hand-maintained cache.

final class CoursesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Course>>,
          List<Course>,
          FutureOr<List<Course>>
        >
    with $FutureModifier<List<Course>>, $FutureProvider<List<Course>> {
  /// Non-archived courses.
  ///
  /// Invalidate after any create, edit or delete so the list rebuilds from the
  /// database rather than from a hand-maintained cache.
  CoursesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'coursesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$coursesHash();

  @$internal
  @override
  $FutureProviderElement<List<Course>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Course>> create(Ref ref) {
    return courses(ref);
  }
}

String _$coursesHash() => r'f3679aed73a2c7fcf04434a18a05d5d9da4292fe';

/// Themes within one course.

@ProviderFor(themes)
final themesProvider = ThemesFamily._();

/// Themes within one course.

final class ThemesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Theme>>,
          List<Theme>,
          FutureOr<List<Theme>>
        >
    with $FutureModifier<List<Theme>>, $FutureProvider<List<Theme>> {
  /// Themes within one course.
  ThemesProvider._({
    required ThemesFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'themesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$themesHash();

  @override
  String toString() {
    return r'themesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<Theme>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Theme>> create(Ref ref) {
    final argument = this.argument as int;
    return themes(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ThemesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$themesHash() => r'e27f6b882f241a06e1c2403661429406e44ce3f9';

/// Themes within one course.

final class ThemesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<Theme>>, int> {
  ThemesFamily._()
    : super(
        retry: null,
        name: r'themesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Themes within one course.

  ThemesProvider call(int courseId) =>
      ThemesProvider._(argument: courseId, from: this);

  @override
  String toString() => r'themesProvider';
}

/// Cards within one theme.

@ProviderFor(cards)
final cardsProvider = CardsFamily._();

/// Cards within one theme.

final class CardsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Card>>,
          List<Card>,
          FutureOr<List<Card>>
        >
    with $FutureModifier<List<Card>>, $FutureProvider<List<Card>> {
  /// Cards within one theme.
  CardsProvider._({
    required CardsFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'cardsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$cardsHash();

  @override
  String toString() {
    return r'cardsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<Card>> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<Card>> create(Ref ref) {
    final argument = this.argument as int;
    return cards(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CardsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$cardsHash() => r'13c680ef508edf8465b5ca4d86e8f3933e463081';

/// Cards within one theme.

final class CardsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<Card>>, int> {
  CardsFamily._()
    : super(
        retry: null,
        name: r'cardsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Cards within one theme.

  CardsProvider call(int themeId) =>
      CardsProvider._(argument: themeId, from: this);

  @override
  String toString() => r'cardsProvider';
}

/// One card by id, for the review screen.
///
/// The session walks cards by id rather than holding whole entities, so a card
/// edited mid-session is not shown from a stale in-memory copy.

@ProviderFor(cardById)
final cardByIdProvider = CardByIdFamily._();

/// One card by id, for the review screen.
///
/// The session walks cards by id rather than holding whole entities, so a card
/// edited mid-session is not shown from a stale in-memory copy.

final class CardByIdProvider
    extends $FunctionalProvider<AsyncValue<Card?>, Card?, FutureOr<Card?>>
    with $FutureModifier<Card?>, $FutureProvider<Card?> {
  /// One card by id, for the review screen.
  ///
  /// The session walks cards by id rather than holding whole entities, so a card
  /// edited mid-session is not shown from a stale in-memory copy.
  CardByIdProvider._({
    required CardByIdFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'cardByIdProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$cardByIdHash();

  @override
  String toString() {
    return r'cardByIdProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Card?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Card?> create(Ref ref) {
    final argument = this.argument as int;
    return cardById(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CardByIdProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$cardByIdHash() => r'6eb99950e7064ea451a157d77c53217dd67c0082';

/// One card by id, for the review screen.
///
/// The session walks cards by id rather than holding whole entities, so a card
/// edited mid-session is not shown from a stale in-memory copy.

final class CardByIdFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Card?>, int> {
  CardByIdFamily._()
    : super(
        retry: null,
        name: r'cardByIdProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One card by id, for the review screen.
  ///
  /// The session walks cards by id rather than holding whole entities, so a card
  /// edited mid-session is not shown from a stale in-memory copy.

  CardByIdProvider call(int cardId) =>
      CardByIdProvider._(argument: cardId, from: this);

  @override
  String toString() => r'cardByIdProvider';
}

/// Cards matching a [CardSearchQuery], ordered by course, theme and card id.
///
/// Scoping and archived-course exclusion live in the repository; matching
/// semantics live in `cardsMatchingQuery`. A blank query returns nothing, so
/// the provider never becomes a "list every card" back door.

@ProviderFor(cardSearchResults)
final cardSearchResultsProvider = CardSearchResultsFamily._();

/// Cards matching a [CardSearchQuery], ordered by course, theme and card id.
///
/// Scoping and archived-course exclusion live in the repository; matching
/// semantics live in `cardsMatchingQuery`. A blank query returns nothing, so
/// the provider never becomes a "list every card" back door.

final class CardSearchResultsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ScopedCard>>,
          List<ScopedCard>,
          FutureOr<List<ScopedCard>>
        >
    with $FutureModifier<List<ScopedCard>>, $FutureProvider<List<ScopedCard>> {
  /// Cards matching a [CardSearchQuery], ordered by course, theme and card id.
  ///
  /// Scoping and archived-course exclusion live in the repository; matching
  /// semantics live in `cardsMatchingQuery`. A blank query returns nothing, so
  /// the provider never becomes a "list every card" back door.
  CardSearchResultsProvider._({
    required CardSearchResultsFamily super.from,
    required CardSearchQuery super.argument,
  }) : super(
         retry: null,
         name: r'cardSearchResultsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$cardSearchResultsHash();

  @override
  String toString() {
    return r'cardSearchResultsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<ScopedCard>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ScopedCard>> create(Ref ref) {
    final argument = this.argument as CardSearchQuery;
    return cardSearchResults(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CardSearchResultsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$cardSearchResultsHash() => r'9cfa51420d009b2fd3b9ef29b870b9fc640f70fe';

/// Cards matching a [CardSearchQuery], ordered by course, theme and card id.
///
/// Scoping and archived-course exclusion live in the repository; matching
/// semantics live in `cardsMatchingQuery`. A blank query returns nothing, so
/// the provider never becomes a "list every card" back door.

final class CardSearchResultsFamily extends $Family
    with
        $FunctionalFamilyOverride<FutureOr<List<ScopedCard>>, CardSearchQuery> {
  CardSearchResultsFamily._()
    : super(
        retry: null,
        name: r'cardSearchResultsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Cards matching a [CardSearchQuery], ordered by course, theme and card id.
  ///
  /// Scoping and archived-course exclusion live in the repository; matching
  /// semantics live in `cardsMatchingQuery`. A blank query returns nothing, so
  /// the provider never becomes a "list every card" back door.

  CardSearchResultsProvider call(CardSearchQuery query) =>
      CardSearchResultsProvider._(argument: query, from: this);

  @override
  String toString() => r'cardSearchResultsProvider';
}

/// Persists onboarding outcomes into the settings row.

@ProviderFor(onboardingService)
final onboardingServiceProvider = OnboardingServiceProvider._();

/// Persists onboarding outcomes into the settings row.

final class OnboardingServiceProvider
    extends
        $FunctionalProvider<
          OnboardingService,
          OnboardingService,
          OnboardingService
        >
    with $Provider<OnboardingService> {
  /// Persists onboarding outcomes into the settings row.
  OnboardingServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'onboardingServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$onboardingServiceHash();

  @$internal
  @override
  $ProviderElement<OnboardingService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  OnboardingService create(Ref ref) {
    return onboardingService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OnboardingService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OnboardingService>(value),
    );
  }
}

String _$onboardingServiceHash() => r'601364a1ae162ba50e45101ab0141924a2a31eab';

/// The API key store. Overridden in tests with an in-memory implementation so
/// no test touches the platform keystore.

@ProviderFor(apiKeyStore)
final apiKeyStoreProvider = ApiKeyStoreProvider._();

/// The API key store. Overridden in tests with an in-memory implementation so
/// no test touches the platform keystore.

final class ApiKeyStoreProvider
    extends $FunctionalProvider<ApiKeyStore, ApiKeyStore, ApiKeyStore>
    with $Provider<ApiKeyStore> {
  /// The API key store. Overridden in tests with an in-memory implementation so
  /// no test touches the platform keystore.
  ApiKeyStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'apiKeyStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$apiKeyStoreHash();

  @$internal
  @override
  $ProviderElement<ApiKeyStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ApiKeyStore create(Ref ref) {
    return apiKeyStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ApiKeyStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ApiKeyStore>(value),
    );
  }
}

String _$apiKeyStoreHash() => r'b8f2afb55c01666cd314edfaddcba67675fef20f';

/// Reads and writes the AI configuration.

@ProviderFor(aiSettingsService)
final aiSettingsServiceProvider = AiSettingsServiceProvider._();

/// Reads and writes the AI configuration.

final class AiSettingsServiceProvider
    extends
        $FunctionalProvider<
          AiSettingsService,
          AiSettingsService,
          AiSettingsService
        >
    with $Provider<AiSettingsService> {
  /// Reads and writes the AI configuration.
  AiSettingsServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiSettingsServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiSettingsServiceHash();

  @$internal
  @override
  $ProviderElement<AiSettingsService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AiSettingsService create(Ref ref) {
    return aiSettingsService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiSettingsService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiSettingsService>(value),
    );
  }
}

String _$aiSettingsServiceHash() => r'a47b57ea4dae93b2a28541d83360cc1e462156f2';

/// The persisted settings row.
///
/// Invalidate after writing preferences so the app re-reads rather than keeping
/// a second copy in memory.

@ProviderFor(appSettings)
final appSettingsProvider = AppSettingsProvider._();

/// The persisted settings row.
///
/// Invalidate after writing preferences so the app re-reads rather than keeping
/// a second copy in memory.

final class AppSettingsProvider
    extends
        $FunctionalProvider<
          AsyncValue<AppSettings>,
          AppSettings,
          FutureOr<AppSettings>
        >
    with $FutureModifier<AppSettings>, $FutureProvider<AppSettings> {
  /// The persisted settings row.
  ///
  /// Invalidate after writing preferences so the app re-reads rather than keeping
  /// a second copy in memory.
  AppSettingsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appSettingsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appSettingsHash();

  @$internal
  @override
  $FutureProviderElement<AppSettings> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AppSettings> create(Ref ref) {
    return appSettings(ref);
  }
}

String _$appSettingsHash() => r'ea8d8521ce68053dda40da0a5cdf5bf62f9a70eb';

/// The active theme mode.
///
/// Falls back to [ThemeMode.system] while settings are loading, which is the
/// correct default: it matches the device rather than flashing a preference the
/// learner never chose.

@ProviderFor(themeMode)
final themeModeProvider = ThemeModeProvider._();

/// The active theme mode.
///
/// Falls back to [ThemeMode.system] while settings are loading, which is the
/// correct default: it matches the device rather than flashing a preference the
/// learner never chose.

final class ThemeModeProvider
    extends $FunctionalProvider<ThemeMode, ThemeMode, ThemeMode>
    with $Provider<ThemeMode> {
  /// The active theme mode.
  ///
  /// Falls back to [ThemeMode.system] while settings are loading, which is the
  /// correct default: it matches the device rather than flashing a preference the
  /// learner never chose.
  ThemeModeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'themeModeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$themeModeHash();

  @$internal
  @override
  $ProviderElement<ThemeMode> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ThemeMode create(Ref ref) {
    return themeMode(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemeMode value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemeMode>(value),
    );
  }
}

String _$themeModeHash() => r'fc7eabb56de3e67323b83a531b3384dd46f7f98c';
