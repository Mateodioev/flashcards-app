import 'package:flashcards2/domain/entities/card.dart' as domain;
import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/entities/theme.dart' as domain;
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/card_editor_screen.dart';
import 'package:flashcards2/presentation/study_session_launcher.dart';
import 'package:flashcards2/presentation/widgets/card_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cards within a theme, with live previews.
///
/// Domain `Card` and `Theme` are imported under a prefix because both names
/// collide with Flutter widgets used throughout this layer.
class CardListScreen extends ConsumerWidget {
  const new({required this.theme, super.key});

  final domain.Theme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(cardsProvider(theme.id));

    return Scaffold(
      appBar: AppBar(title: Text(theme.name)),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          FloatingActionButton.extended(
            heroTag: 'study',
            onPressed: () => _studyTheme(context, ref, theme),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Study'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'addCard',
            onPressed: () => _openEditor(context, ref, theme, null),
            icon: const Icon(Icons.add),
            label: const Text('Card'),
          ),
        ],
      ),
      body: cards.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _LoadError(
          message: 'Could not load cards.',
          onRetry: () => ref.invalidate(cardsProvider(theme.id)),
        ),
        data: (list) {
          if (list.isEmpty) {
            return _EmptyCards(
              onAdd: () => _openEditor(context, ref, theme, null),
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final card = list[index];
              return ListTile(
                onTap: () => _openEditor(context, ref, theme, card),
                // Both sides render through CardContent, so LaTeX previews
                // correctly in the list instead of showing raw dollar signs.
                title: CardContent(card.front),
                subtitle: CardContent(
                  card.back,
                  textStyle: Theme.of(context).textTheme.bodySmall,
                ),
                isThreeLine: true,
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyCards extends StatelessWidget {
  const new({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.style_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No cards yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Add a card, or import one from an image later.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            // Same entry point as the FAB, one tap away instead of making the
            // learner hunt for the floating button.
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: onAdd,
              child: const Text('Create your first card'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const new({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(message),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

Future<void> _openEditor(
  BuildContext context,
  WidgetRef ref,
  domain.Theme theme,
  domain.Card? existing,
) async {
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => CardEditorScreen(theme: theme, existing: existing),
    ),
  );
  if (saved ?? false) {
    ref.invalidate(cardsProvider(theme.id));
  }
}

/// Resolves the theme's course and opens a single-theme study session.
///
/// A theme cannot normally exist without its course (the foreign key cascades),
/// so the null branch is defensive. When it does happen the session still runs
/// with a zero intake cap and blocked ordering — the same graceful degradation
/// the pre-launcher code had — rather than blocking a learner whose due cards
/// are still answerable.
Future<void> _studyTheme(
  BuildContext context,
  WidgetRef ref,
  domain.Theme theme,
) async {
  final course = await ref
      .read(courseRepositoryProvider)
      .findById(theme.courseId);

  if (!context.mounted) return;
  await startStudySession(
    context: context,
    ref: ref,
    course:
        course ??
        Course(
          id: theme.courseId,
          name: '',
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          newCardsPerDay: 0,
          interleaveMode: InterleaveMode.blocked,
          archived: false,
        ),
    theme: theme,
  );
}

/// Re-exported so screens importing this file can reference the domain type
/// without a second prefixed import of their own.
typedef DomainCard = domain.Card;
