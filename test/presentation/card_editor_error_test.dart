import 'package:flashcards2/domain/entities/card.dart' as domain;
import 'package:flashcards2/domain/entities/card_search.dart';
import 'package:flashcards2/domain/entities/scheduling.dart' as sched;
import 'package:flashcards2/domain/entities/theme.dart' as domain;
import 'package:flashcards2/domain/repositories/card_repository.dart';
import 'package:flashcards2/domain/scheduling/due_queue.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/card_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A repository whose writes always fail.
///
/// Exists to exercise the failure path, which is the one that loses data when
/// it is wrong: before the fix, a throwing `createCard` left the screen
/// unchanged, so the tap looked like it had worked and the text was gone.
class _FailingCardRepository implements CardRepository {
  @override
  Future<domain.Card> createCard(domain.Card card) async =>
      throw StateError('disk full');

  @override
  Future<void> updateCard(domain.Card card) async =>
      throw StateError('disk full');

  @override
  Future<void> deleteCard(int id) async => throw StateError('disk full');

  @override
  Future<domain.Card?> findCardById(int id) async => null;

  @override
  Future<List<domain.Card>> findCardsByTheme(int themeId) async =>
      <domain.Card>[];

  @override
  Future<List<ScopedCard>> findCardsWithContext({
    int? courseId,
    int? themeId,
  }) async => <ScopedCard>[];

  @override
  Future<domain.Theme?> findThemeById(int id) async => null;

  @override
  Future<List<domain.Theme>> findThemesByCourse(int courseId) async =>
      <domain.Theme>[];

  @override
  Future<domain.Theme> createTheme(domain.Theme theme) async =>
      throw UnimplementedError();

  @override
  Future<void> updateTheme(domain.Theme theme) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteTheme(int id) async => throw UnimplementedError();

  @override
  Future<domain.CardImage> addImage(domain.CardImage image) async =>
      throw UnimplementedError();

  @override
  Future<List<domain.CardImage>> findImagesByCard(int cardId) async =>
      <domain.CardImage>[];

  @override
  Future<sched.ScheduleState?> findScheduleState(int cardId) async => null;

  @override
  Future<void> upsertScheduleState(sched.ScheduleState state) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteImage(int id) async => throw UnimplementedError();

  @override
  Future<List<DueEntry>> findDueEntries({
    required DateTime dueBefore,
    int? courseId,
    int? themeId,
    int? limit,
  }) async => <DueEntry>[];

  @override
  Future<List<DueEntry>> findNewEntries({
    int? courseId,
    int? themeId,
    int? limit,
  }) async => <DueEntry>[];
}

void main() {
  final theme = domain.Theme(
    id: 1,
    courseId: 1,
    name: 'Cells',
    createdAt: DateTime(2022),
  );

  Widget app(CardRepository repository) {
    return ProviderScope(
      overrides: [cardRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(home: CardEditorScreen(theme: theme)),
    );
  }

  group('a failed save', () {
    testWidgets('reports the failure instead of looking like success', (
      tester,
    ) async {
      await tester.pumpWidget(app(_FailingCardRepository()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Front text');
      await tester.enterText(find.byType(TextField).last, 'Back text');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Could not save the card'),
        findsOneWidget,
        reason: 'the learner must be told, not left guessing',
      );
      expect(
        find.textContaining('Your text is still here'),
        findsOneWidget,
        reason: 'the first worry on a failed save is losing what you wrote',
      );
    });

    testWidgets('keeps the editor open and the text intact', (tester) async {
      await tester.pumpWidget(app(_FailingCardRepository()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Keep me');
      await tester.enterText(find.byType(TextField).last, 'And me');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Still on the editor, as opposed to having popped as if saved.
      expect(find.text('New card'), findsOneWidget);
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(
        fields.map((f) => f.controller?.text),
        containsAll(<String>['Keep me', 'And me']),
        reason: 'a failed save must never discard the input',
      );
    });

    testWidgets('a partial entry keeps Save disabled', (tester) async {
      await tester.pumpWidget(app(_FailingCardRepository()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Only a front');
      await tester.pump();

      final save = tester.widget<TextButton>(
        find.ancestor(of: find.text('Save'), matching: find.byType(TextButton)),
      );
      expect(
        save.onPressed,
        isNull,
        reason: 'a card needs both sides before it is worth saving',
      );
    });
  });
}
