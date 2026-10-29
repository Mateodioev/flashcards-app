import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/entities/theme.dart' as domain;
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/card_list_screen.dart';
import 'package:flashcards2/presentation/screens/card_search_screen.dart';
import 'package:flashcards2/presentation/screens/image_import_screen.dart';
import 'package:flashcards2/presentation/screens/settings_screen.dart';
import 'package:flashcards2/presentation/study_session_launcher.dart';
import 'package:flashcards2/presentation/widgets/card_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Course list, and the entry point to authoring.
class CourseListScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(coursesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Courses'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search cards',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CardSearchScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: 'Import from image',
            onPressed: () async {
              final result = await Navigator.of(context).push<Object?>(
                MaterialPageRoute<Object?>(
                  builder: (_) => const ImageImportScreen(),
                ),
              );
              if (!context.mounted) return;
              reportImageImportResult(context, result);
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          FloatingActionButton.extended(
            heroTag: 'study-global',
            onPressed: () =>
                startGlobalStudySession(context: context, ref: ref),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Study'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'addCourse',
            onPressed: () => _createCourse(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Course'),
          ),
        ],
      ),
      body: courses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: 'Could not load courses.',
          onRetry: () => ref.invalidate(coursesProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return _EmptyState(
              icon: Icons.menu_book_outlined,
              title: 'No courses yet',
              message: 'Create a course to start grouping cards by theme.',
              actionLabel: 'Create your first course',
              onAction: () => _createCourse(context, ref),
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final course = list[index];
              return Dismissible(
                key: ValueKey('course-${course.id}'),
                background: _SwipeBackground(
                  alignment: Alignment.centerLeft,
                  color: Theme.of(context).colorScheme.error,
                  icon: Icons.delete_outline,
                ),
                secondaryBackground: _SwipeBackground(
                  alignment: Alignment.centerRight,
                  color: Theme.of(context).colorScheme.primary,
                  icon: Icons.edit_outlined,
                ),
                // Always returns false: the provider refetch removes the
                // item, so the Dismissible never owns the removal — an async
                // onDismissed would leave a dismissed widget in the tree.
                confirmDismiss: (direction) async {
                  if (direction == DismissDirection.endToStart) {
                    await _renameCourse(context, ref, course);
                    return false;
                  }
                  if (await _confirmDeleteCourse(context, ref, course)) {
                    await ref
                        .read(courseRepositoryProvider)
                        .delete(course.id);
                    ref.invalidate(coursesProvider);
                  }
                  return false;
                },
                // A screen reader cannot perform a swipe, so the row must
                // say what the two gestures do.
                child: Semantics(
                  hint: 'Opens the course. Swipe left to rename; '
                      'swipe right to delete.',
                  child: ListTile(
                    title: Text(course.name),
                    subtitle: Text(
                      course.interleaveMode == InterleaveMode.interleaved
                          ? 'Interleaved practice'
                          : 'Blocked practice',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ThemeListScreen(course: course),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Themes within a course.
class ThemeListScreen extends ConsumerWidget {
  const new({required this.course, super.key});

  final Course course;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themes = ref.watch(themesProvider(course.id));

    return Scaffold(
      appBar: AppBar(title: Text(course.name)),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          FloatingActionButton.extended(
            heroTag: 'study-course',
            onPressed: () =>
                startStudySession(context: context, ref: ref, course: course),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Study'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'addTheme',
            onPressed: () => _createTheme(context, ref, course),
            icon: const Icon(Icons.add),
            label: const Text('Theme'),
          ),
        ],
      ),
      body: themes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: 'Could not load themes.',
          onRetry: () => ref.invalidate(themesProvider(course.id)),
        ),
        data: (list) {
          if (list.isEmpty) {
            return _EmptyState(
              icon: Icons.folder_outlined,
              title: 'No themes yet',
              message: 'Themes group cards inside a course.',
              actionLabel: 'Create your first theme',
              onAction: () => _createTheme(context, ref, course),
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final item = list[index];
              return Dismissible(
                key: ValueKey('theme-${item.id}'),
                background: _SwipeBackground(
                  alignment: Alignment.centerLeft,
                  color: Theme.of(context).colorScheme.error,
                  icon: Icons.delete_outline,
                ),
                secondaryBackground: _SwipeBackground(
                  alignment: Alignment.centerRight,
                  color: Theme.of(context).colorScheme.primary,
                  icon: Icons.edit_outlined,
                ),
                confirmDismiss: (direction) async {
                  if (direction == DismissDirection.endToStart) {
                    await _renameTheme(context, ref, item);
                    return false;
                  }
                  if (await _confirmDeleteTheme(context, ref, item)) {
                    await ref
                        .read(cardRepositoryProvider)
                        .deleteTheme(item.id);
                    ref.invalidate(themesProvider(course.id));
                  }
                  return false;
                },
                // Same disclosure as the course rows above.
                child: Semantics(
                  hint: 'Opens the theme. Swipe left to rename; '
                      'swipe right to delete.',
                  child: ListTile(
                    title: Text(item.name),
                    subtitle: item.description == null
                        ? null
                        : CardContent(item.description!),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CardListScreen(theme: item),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// An empty state never leaves the learner at a dead end: when [actionLabel]
/// and [onAction] are set, the primary way forward is one tap away.
class _EmptyState extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
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

Future<void> _createCourse(BuildContext context, WidgetRef ref) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) =>
        const _NameDialog(title: 'New course', label: 'Course name'),
  );
  if (name == null || name.trim().isEmpty) return;

  await ref
      .read(courseRepositoryProvider)
      .create(
        Course(
          id: 0,
          name: name.trim(),
          createdAt: DateTime.now(),
          newCardsPerDay: 10,
          interleaveMode: InterleaveMode.blocked,
          archived: false,
        ),
      );
  ref.invalidate(coursesProvider);
}

Future<void> _createTheme(
  BuildContext context,
  WidgetRef ref,
  Course course,
) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => const _NameDialog(title: 'New theme', label: 'Theme name'),
  );
  if (name == null || name.trim().isEmpty) return;

  await ref
      .read(cardRepositoryProvider)
      .createTheme(
        domain.Theme(
          id: 0,
          courseId: course.id,
          name: name.trim(),
          createdAt: DateTime.now(),
        ),
      );
  ref.invalidate(themesProvider(course.id));
}

/// Swipe-left on a course: rename it. Returns nothing because the item must
/// never be dismissed for a rename — `confirmDismiss` always reports false.
Future<void> _renameCourse(
  BuildContext context,
  WidgetRef ref,
  Course course,
) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(
      title: 'Rename course',
      label: 'Course name',
      initialValue: course.name,
      confirmText: 'Save',
    ),
  );
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty || trimmed == course.name) return;

  await ref
      .read(courseRepositoryProvider)
      .update(
        Course(
          id: course.id,
          name: trimmed,
          createdAt: course.createdAt,
          newCardsPerDay: course.newCardsPerDay,
          interleaveMode: course.interleaveMode,
          archived: course.archived,
        ),
      );
  ref.invalidate(coursesProvider);
}

/// Swipe-left on a theme: rename it. Same never-dismiss contract as
/// [_renameCourse].
Future<void> _renameTheme(
  BuildContext context,
  WidgetRef ref,
  domain.Theme theme,
) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(
      title: 'Rename theme',
      label: 'Theme name',
      initialValue: theme.name,
      confirmText: 'Save',
    ),
  );
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty || trimmed == theme.name) return;

  await ref
      .read(cardRepositoryProvider)
      .updateTheme(
        domain.Theme(
          id: theme.id,
          courseId: theme.courseId,
          name: trimmed,
          description: theme.description,
          createdAt: theme.createdAt,
        ),
      );
  ref.invalidate(themesProvider(theme.courseId));
}

/// Deletion is irreversible and cascades (course -> themes -> cards ->
/// images, schedule state, review logs and reminder subscriptions), so the
/// first dialog spells out the impact and a second one stands guard.
Future<bool> _confirmDeleteCourse(
  BuildContext context,
  WidgetRef ref,
  Course course,
) async {
  final themes = await ref
      .read(cardRepositoryProvider)
      .findThemesByCourse(course.id);
  final scoped = await ref
      .read(cardRepositoryProvider)
      .findCardsWithContext(courseId: course.id);
  if (!context.mounted) return false;

  final first = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete course?'),
      content: Text(
        'Deleting "${course.name}" will also delete '
        '${_count(themes.length, 'theme')} and '
        '${_count(scoped.length, 'card')}.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (first != true || !context.mounted) return false;

  return await _finalDeleteConfirmation(context);
}

Future<bool> _confirmDeleteTheme(
  BuildContext context,
  WidgetRef ref,
  domain.Theme theme,
) async {
  final scoped = await ref
      .read(cardRepositoryProvider)
      .findCardsWithContext(themeId: theme.id);
  if (!context.mounted) return false;

  final first = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete theme?'),
      content: Text(
        'Deleting "${theme.name}" will also delete '
        '${_count(scoped.length, 'card')}.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (first != true || !context.mounted) return false;

  return await _finalDeleteConfirmation(context);
}

/// The second confirmation, shared by course and theme deletion.
Future<bool> _finalDeleteConfirmation(BuildContext context) async {
  final second = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Really delete?'),
      content: const Text('This cannot be undone.'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete permanently'),
        ),
      ],
    ),
  );
  return second ?? false;
}

String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

/// Reports the image-import result the route pops with. Saving five cards
/// used to silently drop the learner back at the course list — this is the
/// audible "it worked".
void reportImageImportResult(BuildContext context, Object? result) {
  if (result is! ({int count, String theme}) || result.count == 0) return;
  final noun = result.count == 1 ? 'card' : 'cards';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('${result.count} $noun added to "${result.theme}".'),
    ),
  );
}

/// The panel revealed under a dismissing item: red delete on the left
/// (swipe right), primary edit on the right (swipe left).
class _SwipeBackground extends StatelessWidget {
  const new({
    required this.alignment,
    required this.color,
    required this.icon,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Icon(icon, color: Colors.white),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const new({
    required this.title,
    required this.label,
    this.initialValue,
    this.confirmText = 'Create',
  });

  final String title;
  final String label;
  final String? initialValue;
  final String confirmText;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller;

  /// A blank or whitespace-only name must never leave this dialog: before the
  /// guard existed the dialog closed and the caller silently dropped the
  /// value, so "Create" appeared to do nothing.
  bool get _canSubmit => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onNameChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (value) {
          if (_canSubmit) Navigator.of(context).pop(value);
        },
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSubmit
              ? () => Navigator.of(context).pop(_controller.text)
              : null,
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}
