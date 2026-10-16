import 'dart:convert';

import 'package:flashcards2/domain/ai/ai_client.dart';
import 'package:flashcards2/domain/ai/flashcard_prompt.dart';
import 'package:flashcards2/domain/entities/card.dart' as domain;
import 'package:flashcards2/domain/entities/course.dart';
import 'package:flashcards2/domain/entities/theme.dart' as domain;
import 'package:flashcards2/domain/enums.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flashcards2/presentation/widgets/card_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// Imports cards from a photo of study material.
///
/// The flow enforces two rules that are not negotiable:
///  1. a course must be chosen **before** anything is sent anywhere, and
///  2. every generated card is reviewed by the learner before it is saved.
///
/// Both exist because model output is not trustworthy enough to enter a
/// spaced-repetition schedule unread: a wrong card gets memorised as if
/// correct, and the schedule then works against the learner.
class ImageImportScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ImageImportScreen> createState() => _ImageImportScreenState();
}

enum _Stage { chooseCourse, pickImage, generating, review }

class _ImageImportScreenState extends ConsumerState<ImageImportScreen> {
  final _picker = ImagePicker();

  _Stage _stage = _Stage.chooseCourse;
  late Course _course;
  late String _imageBase64;
  late String _mimeType;
  String? _error;
  List<CardDraft> _drafts = const <CardDraft>[];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import from image')),
      body: switch (_stage) {
        _Stage.chooseCourse => _buildCourseChoice(context),
        _Stage.pickImage => _buildPickImage(context),
        _Stage.generating => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Reading the material...'),
            ],
          ),
        ),
        _Stage.review => _buildReview(context),
      },
    );
  }

  /// Step 1: the course gate. Nothing leaves the device before this.
  Widget _buildCourseChoice(BuildContext context) {
    final courses = ref.watch(coursesProvider);

    return courses.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          Center(child: Text('Could not load courses: $error')),
      data: (list) {
        if (list.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Create a course first. Imported cards need somewhere to go, '
                'and the course decides how they are scheduled.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Which course are these cards for?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final course in list)
              ListTile(
                title: Text(course.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => setState(() {
                  _course = course;
                  _stage = _Stage.pickImage;
                }),
              ),
          ],
        );
      },
    );
  }

  /// Step 2: theme selection and image capture.
  Widget _buildPickImage(BuildContext context) {
    final themes = ref.watch(themesProvider(_course.id));

    return themes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Could not load themes: $error')),
      data: (list) {
        if (list.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'This course has no themes yet. Add a theme, then import.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Course: ${_course.name}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: _ErrorBanner(message: _error!),
              ),
            for (final theme in list)
              ListTile(
                title: Text(theme.name),
                subtitle: const Text('Choose a theme, then pick an image'),
                trailing: const Icon(Icons.add_a_photo_outlined),
                onTap: () => _pickAndGenerate(theme),
              ),
          ],
        );
      },
    );
  }

  Future<void> _pickAndGenerate(domain.Theme theme) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      // Downscaled before encoding: a full-resolution phone photo is megabytes
      // of base64 for material that is usually text on paper.
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    setState(() {
      _imageBase64 = base64Encode(bytes);
      _mimeType = picked.mimeType ?? 'image/jpeg';
      _stage = _Stage.generating;
      _error = null;
    });

    await _generate(theme);
  }

  Future<void> _generate(domain.Theme theme) async {
    final settings = ref.read(aiSettingsServiceProvider);
    final config = await settings.read();

    if (config == null || !config.hasModel) {
      setState(() {
        _stage = _Stage.pickImage;
        _error = 'Configure an API and choose a model in Settings first.';
      });
      return;
    }

    try {
      final client = await settings.client();
      final body = await client!.generateCardsFromImage(
        modelId: config.modelId!,
        imageBase64: _imageBase64,
        mimeType: _mimeType,
        systemPrompt: FlashcardPrompt.system,
        instruction: FlashcardPrompt.imageInstruction,
      );

      final parsed = FlashcardPrompt.parse(body);
      if (!mounted) return;

      if (!parsed.hasDrafts) {
        setState(() {
          _stage = _Stage.pickImage;
          _error = parsed.error ?? 'No cards were produced.';
        });
        return;
      }

      setState(() {
        _drafts = parsed.drafts;
        _stage = _Stage.review;
        _error = parsed.dropped > 0
            ? '${parsed.dropped} malformed '
                  '${parsed.dropped == 1 ? 'entry was' : 'entries were'} '
                  'skipped.'
            : null;
        _pendingTheme = theme;
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.pickImage;
        _error = e.message;
      });
    }
  }

  late domain.Theme _pendingTheme;

  /// Step 3: the mandatory review gate. Nothing is saved without approval.
  Widget _buildReview(BuildContext context) {
    return _ReviewDrafts(
      drafts: _drafts,
      notice: _error,
      onCancel: () => setState(() {
        _stage = _Stage.pickImage;
        _drafts = const <CardDraft>[];
      }),
      onSave: _saveApproved,
    );
  }

  Future<void> _saveApproved(List<CardDraft> approved) async {
    final repository = ref.read(cardRepositoryProvider);
    final now = DateTime.now();

    for (final draft in approved) {
      await repository.createCard(
        domain.Card(
          id: 0,
          themeId: _pendingTheme.id,
          front: draft.front,
          back: draft.back,
          source: CardSource.aiGenerated,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    if (!mounted) return;
    ref.invalidate(cardsProvider(_pendingTheme.id));
    Navigator.of(context).pop(approved.length);
  }
}

class _ErrorBanner extends StatelessWidget {
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

/// Review, edit and approve generated drafts before they are persisted.
class _ReviewDrafts extends StatefulWidget {
  const new({
    required this.drafts,
    required this.onCancel,
    required this.onSave,
    this.notice,
  });

  final List<CardDraft> drafts;
  final String? notice;
  final VoidCallback onCancel;
  final ValueChanged<List<CardDraft>> onSave;

  @override
  State<_ReviewDrafts> createState() => _ReviewDraftsState();
}

class _ReviewDraftsState extends State<_ReviewDrafts> {
  late List<_EditableDraft> _editable;

  @override
  void initState() {
    super.initState();
    _editable = <_EditableDraft>[
      for (final d in widget.drafts) _EditableDraft(draft: d),
    ];
  }

  @override
  void dispose() {
    for (final e in _editable) {
      e.front.dispose();
      e.back.dispose();
    }
    super.dispose();
  }

  List<CardDraft> get _approved => <CardDraft>[
    for (final e in _editable)
      if (e.approved.value)
        CardDraft(front: e.front.text.trim(), back: e.back.text.trim()),
  ];

  @override
  Widget build(BuildContext context) {
    final count = _approved.length;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${widget.drafts.length} cards proposed. '
                'Review and edit before saving.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'These came from a model. A wrong card gets memorised as if it '
                'were correct, so check each one.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (widget.notice != null) ...<Widget>[
                const SizedBox(height: 12),
                _ErrorBanner(message: widget.notice!),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: _editable.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) =>
                _DraftEditor(draft: _editable[index], onChanged: _refresh),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    child: const Text('Discard'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: count == 0
                        ? null
                        : () => widget.onSave(_approved),
                    child: Text('Save $count'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _refresh() => setState(() {});
}

class _EditableDraft {
  new({required this.draft})
    : front = TextEditingController(text: draft.front),
      back = TextEditingController(text: draft.back);

  final CardDraft draft;
  final TextEditingController front;
  final TextEditingController back;

  /// Approved by default: the learner rejects what is wrong rather than
  /// accepting what is right, which matches how review actually reads.
  final approved = _BoolValue(value: true);
}

/// Mutable approval flag.
///
/// A small holder rather than a `ValueNotifier`, so the surrounding list
/// rebuild stays explicit and no listener is left dangling.
class _BoolValue {
  new({required this.value});

  bool value;
}

class _DraftEditor extends StatelessWidget {
  const new({required this.draft, required this.onChanged});

  final _EditableDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = draft.approved.value;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Checkbox(
                value: enabled,
                onChanged: (value) {
                  draft.approved.value = value ?? false;
                  onChanged();
                },
              ),
              Text(
                enabled ? 'Will be saved' : 'Rejected',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
          TextField(
            controller: draft.front,
            onChanged: (_) => onChanged(),
            enabled: enabled,
            maxLines: null,
            decoration: const InputDecoration(
              labelText: 'Front',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: draft.back,
            onChanged: (_) => onChanged(),
            enabled: enabled,
            maxLines: null,
            decoration: const InputDecoration(
              labelText: 'Back',
              border: OutlineInputBorder(),
            ),
          ),
          if (enabled) ...<Widget>[
            const SizedBox(height: 12),
            // Rendered with the same widget the review screen uses, so a broken
            // formula is caught here rather than mid-session.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: CardContent(draft.front.text),
            ),
          ],
        ],
      ),
    );
  }
}
