import 'package:flashcards2/domain/entities/card_search.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/card_editor_screen.dart';
import 'package:flashcards2/presentation/search/card_search.dart';
import 'package:flashcards2/presentation/widgets/card_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global card search across every non-archived course (T5.7).
///
/// The screen is a lookup, not a browsing surface: with a blank query it
/// shows nothing, and every result carries its Course › Theme trail so the
/// learner can tell duplicates in different courses apart.
class CardSearchScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<CardSearchScreen> createState() => _CardSearchScreenState();
}

class _CardSearchScreenState extends ConsumerState<CardSearchScreen> {
  final _controller = TextEditingController();

  int? _courseId;
  int? _themeId;

  /// Theme chips make sense only inside a chosen course, so changing the
  /// course always clears the theme.
  void _selectCourse(int? courseId) {
    setState(() {
      _courseId = courseId;
      _themeId = null;
    });
  }

  void _selectTheme(int? themeId) {
    setState(() => _themeId = themeId);
  }

  CardSearchQuery get _query => (
    text: _controller.text,
    courseId: _courseId,
    themeId: _themeId,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(cardSearchResultsProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search cards',
            border: InputBorder.none,
          ),
          // The empty body is intentional: rebuild so `_query` re-reads the
          // controller's text and the results provider gets the new record.
          onChanged: (_) => setState(() {}),
        ),
        actions: <Widget>[
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear',
              onPressed: () => setState(_controller.clear),
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _ScopeChips(
            courseId: _courseId,
            themeId: _themeId,
            onCourse: _selectCourse,
            onTheme: _selectTheme,
          ),
          Expanded(child: _buildResults(results)),
        ],
      ),
    );
  }

  Widget _buildResults(AsyncValue<List<ScopedCard>> results) {
    if (isBlankQuery(_controller.text)) {
      return const _IdleState();
    }
    return results.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _SearchError(
        onRetry: () => ref.invalidate(cardSearchResultsProvider(_query)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Text('No results for "${_controller.text.trim()}"'),
          );
        }
        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final result = list[index];
            return ListTile(
              onTap: () => _openEditor(context, result),
              // Front renders through CardContent, so LaTeX previews in the
              // result instead of showing raw dollar signs.
              title: CardContent(result.card.front),
              subtitle: Text('${result.courseName} › ${result.theme.name}'),
            );
          },
        );
      },
    );
  }

  Future<void> _openEditor(BuildContext context, ScopedCard result) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            CardEditorScreen(theme: result.theme, existing: result.card),
      ),
    );
    // A saved edit may have changed the match itself, so re-run the lookup
    // rather than showing the now-stale row.
    if (changed ?? false) {
      ref.invalidate(cardSearchResultsProvider);
    }
  }
}

/// Course and theme scope filters, cascading: themes appear only once a
/// course is chosen.
class _ScopeChips extends ConsumerWidget {
  const new({
    required this.courseId,
    required this.themeId,
    required this.onCourse,
    required this.onTheme,
  });

  final int? courseId;
  final int? themeId;
  final ValueChanged<int?> onCourse;
  final ValueChanged<int?> onTheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(coursesProvider);
    return courses.maybeWhen(
      data: (list) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _ChipRow(
            allLabel: 'All courses',
            selectedId: courseId,
            options: [
              for (final course in list) (id: course.id, label: course.name),
            ],
            onSelect: onCourse,
          ),
          if (courseId != null)
            ref
                .watch(themesProvider(courseId!))
                .maybeWhen(
                  data: (themes) => _ChipRow(
                    allLabel: 'All themes',
                    selectedId: themeId,
                    options: [
                      for (final theme in themes)
                        (id: theme.id, label: theme.name),
                    ],
                    onSelect: onTheme,
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
        ],
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const new({
    required this.allLabel,
    required this.selectedId,
    required this.options,
    required this.onSelect,
  });

  final String allLabel;
  final int? selectedId;
  final List<({int id, String label})> options;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(allLabel),
              selected: selectedId == null,
              onSelected: (_) => onSelect(null),
            ),
          ),
          for (final option in options)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(option.label),
                selected: selectedId == option.id,
                onSelected: (_) =>
                    onSelect(selectedId == option.id ? null : option.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _IdleState extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.search, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('Search your cards', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Type to find cards across every course by text or LaTeX.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchError extends StatelessWidget {
  const new({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('Could not run the search.'),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
