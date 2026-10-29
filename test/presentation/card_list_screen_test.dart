import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/domain/entities/theme.dart' as domain;
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/card_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Card list empty state: it must offer the same create entry point as the
/// FAB instead of leaving the learner at a dead end.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Widget app() {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: CardListScreen(
          theme: domain.Theme(
            id: 1,
            courseId: 1,
            name: 'Cells',
            createdAt: DateTime(2026),
          ),
        ),
      ),
    );
  }

  testWidgets('the empty card list offers to create one', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('No cards yet'), findsOneWidget);
    await tester.tap(find.text('Create your first card'));
    await tester.pumpAndSettle();

    expect(find.text('New card'), findsOneWidget);
  });
}
