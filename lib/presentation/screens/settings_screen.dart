import 'package:flashcards2/domain/entities/scheduling.dart';
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App preferences.
///
/// Writes through the repository and invalidates the settings provider, so the
/// app re-reads from the database rather than keeping a second copy in memory
/// that could drift from the stored value.
class SettingsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('Could not load settings.'),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => ref.invalidate(appSettingsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (value) => ListView(
          children: <Widget>[
            const _SectionHeader('Appearance'),
            // `RadioListTile.groupValue`/`onChanged` are deprecated in this
            // Flutter; the group now owns the selection and the tiles only
            // declare their own value.
            RadioGroup<AppThemeMode>(
              groupValue: value.themeMode,
              onChanged: (selected) async {
                if (selected == null) return;
                await _setTheme(ref, selected);
              },
              child: Column(
                children: <Widget>[
                  for (final mode in AppThemeMode.values)
                    RadioListTile<AppThemeMode>(
                      value: mode,
                      title: Text(_themeLabel(mode)),
                      subtitle: mode == AppThemeMode.system
                          ? const Text('Follows your device setting')
                          : null,
                    ),
                ],
              ),
            ),
            const Divider(),
            const _SectionHeader('Scheduling'),
            ListTile(
              title: const Text('Day starts at'),
              subtitle: Text(
                '${value.dayCutoffHour.toString().padLeft(2, '0')}:00 — a '
                'review before this still counts as the previous day',
              ),
            ),
            const Divider(),
            const _SectionHeader('Onboarding'),
            ListTile(
              title: const Text('Working memory span'),
              subtitle: Text(
                value.memorySpan == null
                    ? 'Not measured'
                    : '${value.memorySpan} items',
              ),
            ),
            SwitchListTile(
              value: value.forcedGenerationBarrier,
              onChanged: (enabled) => _setBarrier(ref, enabled),
              title: const Text('Require recall before revealing'),
              subtitle: const Text(
                'The answer stays hidden until you attempt it. Useful if you '
                'tend to recognise answers without recalling them.',
              ),
            ),
            const Divider(),
            const _SectionHeader('AI import'),
            const ListTile(
              title: Text('Image to flashcards'),
              subtitle: Text('Configured in List 8'),
              enabled: false,
            ),
          ],
        ),
      ),
    );
  }

  static String _themeLabel(AppThemeMode mode) {
    return switch (mode) {
      AppThemeMode.system => 'Match device',
      AppThemeMode.light => 'Light',
      AppThemeMode.dark => 'Dark',
    };
  }
}

Future<void> _setTheme(WidgetRef ref, AppThemeMode mode) async {
  final repository = ref.read(settingsRepositoryProvider);
  final current = await repository.read();
  await repository.update(current.copyWith(themeMode: mode));
  ref.invalidate(appSettingsProvider);
}

Future<void> _setBarrier(WidgetRef ref, bool enabled) async {
  final repository = ref.read(settingsRepositoryProvider);
  final current = await repository.read();
  await repository.update(current.copyWith(forcedGenerationBarrier: enabled));
  ref.invalidate(appSettingsProvider);
}

class _SectionHeader extends StatelessWidget {
  const new(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Exposed for the settings-navigation entry point.
const String settingsTitle = 'Settings';

/// Re-exported so callers do not need a second import for the entity type.
typedef AppSettingsEntity = AppSettings;
