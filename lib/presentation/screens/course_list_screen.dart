import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/entities/theme.dart' as domain;
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/screens/card_list_screen.dart';
import 'package:flashcards2/presentation/screens/settings_screen.dart';
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
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createCourse(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Course'),
      ),
      body: courses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: 'Could not load courses.',
          onRetry: () => ref.invalidate(coursesProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const _EmptyState(
              icon: Icons.menu_book_outlined,
              title: 'No courses yet',
              message: 'Create a course to start grouping cards by theme.',
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final course = list[index];
              return ListTile(
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createTheme(context, ref, course),
        icon: const Icon(Icons.add),
        label: const Text('Theme'),
      ),
      body: themes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: 'Could not load themes.',
          onRetry: () => ref.invalidate(themesProvider(course.id)),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const _EmptyState(
              icon: Icons.folder_outlined,
              title: 'No themes yet',
              message: 'Themes group cards inside a course.',
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final item = list[index];
              return ListTile(
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
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const new({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

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

class _NameDialog extends StatefulWidget {
  const new({required this.title, required this.label});

  final String title;
  final String label;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
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
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
