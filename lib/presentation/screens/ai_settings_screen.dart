import 'dart:async';

import 'package:flashcards2/domain/ai/ai_client.dart';
import 'package:flashcards2/domain/ai/ai_settings_service.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Configures the OpenAI-compatible endpoint used for image import.
///
/// Two rules shape this screen:
///
///  1. **The stored key is never rendered back into the field.** It is either
///     absent entirely (an "API key" field waiting for input) or summarised as
///     "a key is stored" with an explicit Replace action. A settings screen
///     that reads a secret out of secure storage and paints it in a text field
///     has undone the reason it was put there.
///  2. **Nothing is persisted until it has been verified.** A key that has
///     never authenticated is not a configuration, it is a guess; storing it
///     would leave the import feature enabled against a broken endpoint.
class AiSettingsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final _baseUrl = TextEditingController();
  final _apiKey = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  bool _hasStoredKey = false;
  bool _replacingKey = false;
  String? _modelId;
  DateTime? _configuredAt;

  /// Models from the most recent successful verification. Held in state rather
  /// than in a provider: the list is a live fetch of the endpoint's current
  /// catalogue, not durable state worth caching across screens.
  List<AiModel> _models = const <AiModel>[];
  bool _showAllModels = false;

  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final service = ref.read(aiSettingsServiceProvider);
    final config = await service.read();
    final row = await ref.read(settingsRepositoryProvider).read();

    if (!mounted) return;
    setState(() {
      _loading = false;
      _baseUrl.text = row.apiBaseUrl ?? AiSettingsService.kDefaultBaseUrl;
      _modelId = row.apiModelId;
      _configuredAt = row.apiConfiguredAt;
      // Note what is stored without ever reading it into the field.
      _hasStoredKey = config != null;
    });
  }

  /// The key to use for a request: the freshly typed one, or the stored one.
  Future<String?> _effectiveKey() {
    final typed = _apiKey.text.trim();
    if (typed.isNotEmpty) return Future<String?>.value(typed);
    return ref.read(apiKeyStoreProvider).read();
  }

  Future<void> _verify() async {
    final baseUrl = _baseUrl.text.trim();
    if (baseUrl.isEmpty) {
      setState(() => _error = 'Enter a base URL.');
      return;
    }

    final key = (await _effectiveKey())?.trim();
    if (key == null || key.isEmpty) {
      setState(() => _error = 'Enter an API key.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    final service = ref.read(aiSettingsServiceProvider);
    final result = await service.testCredentials(baseUrl: baseUrl, apiKey: key);

    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _busy = false;
        // A failed check must not leave a previously verified model selectable
        // as though it still worked.
        _models = const <AiModel>[];
        _error = result.message ?? 'The credentials were rejected.';
      });
      return;
    }

    setState(() {
      _busy = false;
      _models = result.models;
      _notice = 'Connected. ${result.models.length} models available.';
      // A newly typed key is kept only after it authenticates.
      _hasStoredKey = true;
      _replacingKey = false;
    });

    // Persist only now, and only the key the learner actually typed. An
    // unchanged stored key is left alone rather than rewritten.
    if (_apiKey.text.trim().isNotEmpty) {
      await service.storeVerifiedKey(_apiKey.text.trim());
      _apiKey.clear();
      if (mounted) setState(() {});
    }
  }

  Future<void> _selectModel(AiModel model) async {
    final service = ref.read(aiSettingsServiceProvider);
    await service.save(
      baseUrl: _baseUrl.text.trim(),
      modelId: model.id,
      verifiedAt: DateTime.now(),
      // No key passed: the stored one is reused, never re-entered.
    );
    if (!mounted) return;
    setState(() {
      _modelId = model.id;
      _configuredAt = DateTime.now();
      _notice = null;
    });
  }

  Future<void> _clear() async {
    await ref.read(aiSettingsServiceProvider).clear();
    if (!mounted) return;
    setState(() {
      _models = const <AiModel>[];
      _modelId = null;
      _configuredAt = null;
      _hasStoredKey = false;
      _replacingKey = false;
      _apiKey.clear();
      _notice = 'Configuration removed.';
      _error = null;
    });
  }

  /// Vision-capable first, then models whose capability the endpoint does not
  /// declare. A model the endpoint says is text-only is hidden behind a toggle
  /// rather than removed, because that claim could be wrong.
  List<AiModel> get _visibleModels {
    if (_showAllModels) return _models;
    return _models
        .where((model) => model.supportsVision != false)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Image to flashcards')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                const Text(
                  'Cards are generated by a model you choose. The image and '
                  'the key are sent to that endpoint and nowhere else.',
                ),
                const SizedBox(height: 20),

                TextField(
                  controller: _baseUrl,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    helperText:
                        'Include the version segment, for example '
                        '/openai/v1',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                if (_replacingKey || !_hasStoredKey)
                  TextField(
                    controller: _apiKey,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'API key',
                      helperText:
                          'Stored in the system keystore, never in the '
                          'app database',
                      border: const OutlineInputBorder(),
                      suffixIcon: _hasStoredKey
                          ? IconButton(
                              icon: const Icon(Icons.close),
                              tooltip: 'Keep the stored key',
                              onPressed: () => setState(() {
                                _replacingKey = false;
                                _apiKey.clear();
                              }),
                            )
                          : null,
                    ),
                  )
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('A key is stored'),
                    subtitle: const Text(
                      'It is not shown here. Enter a new one to replace it.',
                    ),
                    trailing: TextButton(
                      onPressed: () => setState(() => _replacingKey = true),
                      child: const Text('Replace'),
                    ),
                  ),

                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _verify,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verify and list models'),
                ),

                if (_error != null) ...<Widget>[
                  const SizedBox(height: 16),
                  _Banner(
                    message: _error!,
                    icon: Icons.error_outline,
                    color: Theme.of(context).colorScheme.errorContainer,
                    onColor: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ],
                if (_notice != null) ...<Widget>[
                  const SizedBox(height: 16),
                  _Banner(
                    message: _notice!,
                    icon: Icons.check_circle_outline,
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    onColor: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ],

                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                _StatusBlock(
                  modelId: _modelId,
                  configuredAt: _configuredAt,
                  hasKey: _hasStoredKey,
                ),

                if (_models.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  const Divider(),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Choose a model',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        '${_visibleModels.length} shown',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Image import needs a model that accepts images. Models '
                    'marked "vision" were declared as such by the endpoint.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _showAllModels,
                    onChanged: (value) =>
                        setState(() => _showAllModels = value),
                    title: const Text('Show text-only models too'),
                  ),
                  for (final model in _visibleModels)
                    _ModelTile(
                      model: model,
                      selected: model.id == _modelId,
                      onSelected: () => _selectModel(model),
                    ),
                  if (_visibleModels.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No image-capable model was listed by this endpoint. '
                        'Turn on "Show text-only models too" to see the rest.',
                      ),
                    ),
                ],

                if (_hasStoredKey) ...<Widget>[
                  const SizedBox(height: 24),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('Remove configuration'),
                    subtitle: const Text(
                      'Deletes the stored key and the chosen model.',
                    ),
                    onTap: _confirmClear,
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove the API configuration?'),
        content: const Text(
          'The stored key is deleted from the keystore and image import stops '
          'working. Your cards are not affected.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await _clear();
  }
}

class _ModelTile extends StatelessWidget {
  const new({
    required this.model,
    required this.selected,
    required this.onSelected,
  });

  final AiModel model;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Null is unknown, not unsupported: a plain OpenAI-compatible endpoint
    // returns only an id, and calling that "no vision" would misreport it.
    final (String label, Color color) = switch (model.supportsVision) {
      true => ('vision', scheme.primary),
      false => ('text only', scheme.outline),
      null => ('vision unknown', scheme.tertiary),
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(model.label),
      subtitle: Text(
        model.displayName == null ? model.id : '${model.id}\n$label',
      ),
      isThreeLine: model.displayName != null,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? scheme.primary : null,
      ),
      trailing: model.supportsVision == true
          ? Chip(
              label: const Text('vision'),
              labelStyle: TextStyle(color: color, fontSize: 11),
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: color),
            )
          : null,
      onTap: onSelected,
    );
  }
}

class _StatusBlock extends StatelessWidget {
  const new({
    required this.modelId,
    required this.configuredAt,
    required this.hasKey,
  });

  final String? modelId;
  final DateTime? configuredAt;
  final bool hasKey;

  @override
  Widget build(BuildContext context) {
    final ready = hasKey && modelId != null && modelId!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              ready ? Icons.check_circle : Icons.info_outline,
              size: 18,
              color: ready
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ready
                    ? 'Image import is enabled.'
                    : 'Image import is disabled until a key is stored and a '
                          'model is chosen.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        if (modelId != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 26),
            child: Text(
              'Model: $modelId',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (configuredAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 26),
            child: Text(
              // Stated as a past event rather than a standing guarantee:
              // the key can be revoked at the provider at any time.
              'Last verified ${_format(configuredAt!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  static String _format(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}

class _Banner extends StatelessWidget {
  const new({
    required this.message,
    required this.icon,
    required this.color,
    required this.onColor,
  });

  final String message;
  final IconData icon;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: onColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: onColor)),
          ),
        ],
      ),
    );
  }
}
