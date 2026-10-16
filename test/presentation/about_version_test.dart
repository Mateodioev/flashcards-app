import 'package:drift/native.dart';
import 'package:flashcards2/data/database.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The version the learner sees must come from the package, not a hardcoded
/// string that drifts from pubspec. `setMockInitialValues` stands in for the
/// platform channel, which does not exist in a widget test.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    PackageInfo.setMockInitialValues(
      appName: 'TestApp',
      packageName: 'dev.test.app',
      version: '9.8.7',
      buildNumber: '654',
      buildSignature: '',
    );
  });
  tearDown(() => db.close());

  testWidgets('settings shows the package version and build', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Feast for one, famine for many: the version must scroll into view, so
    // scroll to it instead of trusting it to be on screen already.
    await tester.scrollUntilVisible(
      find.text('About'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('About'), findsOneWidget);
    expect(
      find.text('TestApp 9.8.7 (654)'),
      findsOneWidget,
      reason: 'the string must be built from PackageInfo, not hardcoded',
    );
  });
}
