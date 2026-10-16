import 'package:flashcards2/domain/entities/card.dart' as domain;
import 'package:flashcards2/domain/entities/theme.dart' as domain;
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/presentation/markup/math_markup.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/widgets/card_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Create or edit one card, with a live preview of both sides.
///
/// The preview is not decoration. A card whose LaTeX is broken is worse than a
/// card with no LaTeX, because the learner discovers it mid-review — so the
/// author sees the rendered result while typing, in both themes.
class CardEditorScreen extends ConsumerStatefulWidget {
  const new({required this.theme, this.existing, super.key});

  final domain.Theme theme;

  /// Null when creating.
  final domain.Card? existing;

  @override
  ConsumerState<CardEditorScreen> createState() => _CardEditorScreenState();
}

class _CardEditorScreenState extends ConsumerState<CardEditorScreen> {
  late final TextEditingController _front;
  late final TextEditingController _back;
  final _frontFocus = FocusNode();
  final _backFocus = FocusNode();

  bool get _isEditing => widget.existing != null;

  /// True while a save is in flight, so a double tap cannot create two cards.
  bool _saving = false;

  /// A save failure, kept on screen so the text is not lost with it.
  String? _error;

  @override
  void initState() {
    super.initState();
    _front = TextEditingController(text: widget.existing?.front ?? '');
    _back = TextEditingController(text: widget.existing?.back ?? '');
  }

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    _frontFocus.dispose();
    _backFocus.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _front.text.trim().isNotEmpty && _back.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final repository = ref.read(cardRepositoryProvider);
    final now = DateTime.now();

    try {
      if (_isEditing) {
        final existing = widget.existing!;
        await repository.updateCard(
          domain.Card(
            id: existing.id,
            themeId: existing.themeId,
            front: _front.text.trim(),
            back: _back.text.trim(),
            source: existing.source,
            createdAt: existing.createdAt,
            updatedAt: now,
          ),
        );
      } else {
        await repository.createCard(
          domain.Card(
            id: 0,
            themeId: widget.theme.id,
            front: _front.text.trim(),
            back: _back.text.trim(),
            source: CardSource.manual,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    } on Object catch (e) {
      // Without this the screen simply stayed put on a failure: the tap looked
      // like it worked and the learner's text was silently dropped. Losing an
      // authored card without a word is worse than an ugly error.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            'Could not save the card. Your text is still here — try '
            'again.\n\n$e';
      });
      return;
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete card?'),
        content: const Text('This cannot be undone.'),
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
    if (confirmed ?? false) {
      try {
        await ref.read(cardRepositoryProvider).deleteCard(widget.existing!.id);
      } on Object catch (e) {
        if (!mounted) return;
        setState(() => _error = 'Could not delete the card.\n\n$e');
        return;
      }
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  /// Inserts a `$` pair at the caret so the author does not fight the keyboard.
  void _wrapSelection(TextEditingController controller) {
    final selection = controller.selection;
    final text = controller.text;
    if (!selection.isValid) return;

    final selected = selection.textInside(text);
    final replacement = '\$$selected\$';
    controller.value = TextEditingValue(
      text: text.replaceRange(selection.start, selection.end, replacement),
      selection: TextSelection.collapsed(
        offset: selection.start + replacement.length,
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit card' : 'New card'),
        actions: <Widget>[
          if (_isEditing)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
            ),
          TextButton(
            onPressed: _canSave && !_saving ? _save : null,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (_error != null) ...<Widget>[
            _SaveError(message: _error!),
            const SizedBox(height: 12),
          ],
          _Field(
            label: 'Front',
            controller: _front,
            focusNode: _frontFocus,
            onChanged: () => setState(() {}),
            onInsertMath: () => _wrapSelection(_front),
          ),
          const SizedBox(height: 16),
          _Preview(title: 'Front preview', source: _front.text),
          const SizedBox(height: 24),
          _Field(
            label: 'Back',
            controller: _back,
            focusNode: _backFocus,
            onChanged: () => setState(() {}),
            onInsertMath: () => _wrapSelection(_back),
          ),
          const SizedBox(height: 16),
          _Preview(title: 'Back preview', source: _back.text),
          const SizedBox(height: 32),
          const _SyntaxHelp(),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const new({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onInsertMath,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onChanged;
  final VoidCallback onInsertMath;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: (_) => onChanged(),
      minLines: 3,
      maxLines: 8,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        alignLabelWithHint: true,
        suffixIcon: IconButton(
          onPressed: onInsertMath,
          icon: const Icon(Icons.functions),
          tooltip: 'Wrap selection in math',
        ),
      ),
    );
  }
}

/// Live render of whatever is typed, in the current theme.
class _Preview extends StatelessWidget {
  const new({required this.title, required this.source});

  final String title;
  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          if (source.trim().isEmpty)
            Text(
              'Nothing to preview yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            )
          else
            CardContent(source),
        ],
      ),
    );
  }
}

class _SyntaxHelp extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Math syntax', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        const CardContent(r'inline  $\frac{1}{2}$'),
        const SizedBox(height: 4),
        const CardContent(r'display $$\sum_{i=1}^{n} x_i$$'),
        const SizedBox(height: 4),
        const CardContent(r'literal dollar  \$5'),
        const SizedBox(height: 8),
        Text(
          'An unclosed dollar is shown as text, so prices are never swallowed.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Parsed as ${parseMathSegments(r'$x$').length} segments for '
          '${hasMath(r'$x$') ? 'math' : 'text'} input.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

/// A failed save or delete, shown in place of the form.
///
/// The message deliberately says the text is still present: the learner's first
/// worry on a failed save is whether they lost what they wrote, and the answer
/// is no.
class _SaveError extends StatelessWidget {
  const new({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
