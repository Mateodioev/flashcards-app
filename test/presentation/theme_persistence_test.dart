import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/domain/entities/scheduling.dart';
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/main.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Widget app() {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const FlashcardsApp(),
    );
  }

  group('AppSettings.copyWith', () {
    test('changes only the named field', () {
      const original = AppSettings(
        id: AppSettings.singletonId,
        themeMode: AppThemeMode.system,
        dayCutoffHour: 4,
        memorySpan: 5,
        forcedGenerationBarrier: true,
      );

      final updated = original.copyWith(themeMode: AppThemeMode.dark);

      expect(updated.themeMode, AppThemeMode.dark);
      expect(updated.dayCutoffHour, 4, reason: 'untouched fields must survive');
      expect(updated.memorySpan, 5);
      expect(updated.forcedGenerationBarrier, isTrue);
    });

    test('with no arguments returns an equivalent row', () {
      const original = AppSettings(
        id: AppSettings.singletonId,
        themeMode: AppThemeMode.light,
        dayCutoffHour: 2,
      );
      final copy = original.copyWith();
      expect(copy.themeMode, AppThemeMode.light);
      expect(copy.dayCutoffHour, 2);
    });
  });

  group('theme mode persistence', () {
    testWidgets('defaults to matching the device', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.system);
    });

    testWidgets('choosing Dark persists and applies', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.dark);

      // And it reached the database, not just memory.
      final row = await db.select(db.appSettings).getSingle();
      expect(row.themeMode, AppThemeMode.dark);
    });

    testWidgets('a stored preference is applied on relaunch', (tester) async {
      // Simulates a second launch: the row already says light, and the app must
      // honour it before the learner touches anything.
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              id: const Value(AppSettings.singletonId),
              themeMode: const Value(AppThemeMode.light),
            ),
          );

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.light);
    });

    testWidgets('switching back to Match device persists', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Match device'));
      await tester.pumpAndSettle();

      final row = await db.select(db.appSettings).getSingle();
      expect(row.themeMode, AppThemeMode.system);
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.system);
    });
  });

  group('barrier preference', () {
    testWidgets('toggling it persists', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Require recall before revealing'), findsOneWidget);
      await tester.tap(find.text('Require recall before revealing'));
      await tester.pumpAndSettle();

      final row = await db.select(db.appSettings).getSingle();
      expect(row.forcedGenerationBarrier, isTrue);
    });
  });

  group('settings screen', () {
    testWidgets('reports an unmeasured span honestly', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(
        find.text('Not measured'),
        findsOneWidget,
        reason: 'onboarding has not run, and the UI must not invent a number',
      );
    });

    testWidgets('shows the measured span once it exists', (tester) async {
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              id: const Value(AppSettings.singletonId),
              memorySpan: const Value(5),
            ),
          );

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('5 items'), findsOneWidget);
    });

    testWidgets('both themes render without overflow', (tester) async {
      for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
        await db.delete(db.appSettings).go();
        await db
            .into(db.appSettings)
            .insert(
              AppSettingsCompanion.insert(
                id: const Value(AppSettings.singletonId),
                themeMode: Value(mode),
              ),
            );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              home: const SettingsScreen(),
              theme: ThemeData(
                brightness: mode == AppThemeMode.dark
                    ? Brightness.dark
                    : Brightness.light,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });
}
