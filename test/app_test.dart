import 'package:flashcards2/core/theme.dart';
import 'package:flashcards2/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTheme', () {
    test('light and dark share a seed and differ only in brightness', () {
      expect(AppTheme.light.colorScheme.brightness, Brightness.light);
      expect(AppTheme.dark.colorScheme.brightness, Brightness.dark);
      expect(AppTheme.light.useMaterial3, isTrue);
    });
  });

  group('FlashcardsApp', () {
    testWidgets('boots and renders its title', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: FlashcardsApp()));

      expect(find.text('Flashcards'), findsOneWidget);
      expect(find.text('No courses yet.'), findsOneWidget);
    });
  });
}
