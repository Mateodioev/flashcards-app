import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/data/repositories/drift_settings_repository.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settings screen: the day cutoff is user-editable, the measured memory span
/// is display-only, and the pre-existing toggles keep writing through.
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
      child: const MaterialApp(home: SettingsScreen()),
    );
  }

  Future<int> cutoff() async {
    return (await DriftSettingsRepository(db).read()).dayCutoffHour;
  }

  testWidgets(
    'tapping Day starts at opens the cutoff dialog and saving persists',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(await cutoff(), 4);

      await tester.tap(find.text('Day starts at'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(AlertDialog, 'Day starts at'),
        findsOneWidget,
      );

      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('05:00').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(await cutoff(), 5);
      expect(find.textContaining('05:00'), findsOneWidget);
    },
  );

  testWidgets('the working-memory span row is display-only', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final tile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Working memory span'),
    );
    expect(tile.onTap, isNull);
    expect(tile.enabled, isFalse);
  });

  testWidgets('the barrier switch still writes through to storage', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // The settings ListView inflates elements lazily, so below-the-fold rows
    // do not exist until scrolled into view; ensureVisible cannot find them.
    final switchTile = find.text('Require recall before revealing');
    await tester.scrollUntilVisible(switchTile, 300);
    await tester.pumpAndSettle();
    await tester.tap(switchTile);
    await tester.pumpAndSettle();

    expect(
      (await DriftSettingsRepository(db).read()).forcedGenerationBarrier,
      isTrue,
    );
  });
}
