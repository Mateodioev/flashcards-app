import 'package:flashcards2/domain/backup/backup.dart';
import 'package:flashcards2/presentation/backup/backup_files.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Export and restore, on the settings screen.
///
/// Two behaviours are deliberate:
///
///  * **Export says where the file went.** A backup the learner cannot find is
///    not a backup. The path is shown rather than copied to the clipboard
///    silently, because a silent clipboard write is invisible.
///  * **Restore is additive and says so.** Nothing is deleted, so a wrong
///    import costs clutter, not data. That is what makes it safe to offer
///    without a scary confirmation, and the dialog states it plainly rather
///    than asking the learner to trust it.
class BackupSection extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<BackupSection> {
  /// True only while a *write* is in flight.
  ///
  /// Deliberately not set while the confirmation dialog is open: a spinner
  /// there would claim work was happening when the app is in fact waiting for
  /// the learner. It also made `pumpAndSettle` hang forever, because the
  /// progress indicator animates until it is torn down.
  bool _writing = false;

  /// True while reading and parsing the chosen file.
  bool _reading = false;

  bool get _busy => _writing || _reading;
  String? _message;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.download_outlined),
          title: const Text('Export a backup'),
          subtitle: const Text(
            'Writes a JSON file to this device. Your API key is never '
            'included.',
          ),
          trailing: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: _busy ? null : _export,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.upload_outlined),
          title: const Text('Restore from a backup'),
          subtitle: const Text(
            'Adds the courses in the file. Nothing currently on this device is '
            'deleted.',
          ),
          onTap: _busy ? null : _chooseAndImport,
        ),
        if (_message != null) ...<Widget>[
          const SizedBox(height: 8),
          _Note(message: _message!, isError: false),
        ],
        if (_error != null) ...<Widget>[
          const SizedBox(height: 8),
          _Note(message: _error!, isError: true),
        ],
      ],
    );
  }

  Future<void> _export() async {
    setState(() {
      _writing = true;
      _error = null;
      _message = null;
    });

    try {
      final backup = await ref.read(backupExporterProvider).export();
      final path = await ref.read(backupFilesProvider).write(backup);
      if (!mounted) return;
      setState(() {
        _writing = false;
        _message =
            'Backed up ${backup.cardCount} '
            '${backup.cardCount == 1 ? 'card' : 'cards'} to:\n$path';
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _writing = false;
        _error = 'Could not write the backup.\n\n$e';
      });
    }
  }

  Future<void> _chooseAndImport() async {
    final path = await _askForPath();
    if (path == null || path.isEmpty || !mounted) return;

    setState(() {
      _reading = true;
      _error = null;
      _message = null;
    });

    final Backup backup;
    try {
      // Parsing and validation happen before anything is written, so a damaged
      // file cannot leave a half-imported database behind.
      backup = await ref.read(backupFilesProvider).read(path);
    } on BackupFormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _reading = false;
        _error = '${e.message}\n\nNothing was imported.';
      });
      return;
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _reading = false;
        _error = 'Could not read that file.\n\n$e';
      });
      return;
    }

    if (!mounted) return;

    // Reading is finished. Clearing this BEFORE the dialog is what stops the
    // progress indicator: leaving it set kept a spinner animating behind the
    // confirmation, which both never settled and told the learner that work was
    // happening while the app was in fact waiting for them.
    setState(() => _reading = false);

    final confirmed = await _confirm(backup);
    if (confirmed != true) return;

    setState(() => _writing = true);
    try {
      final summary = await ref.read(backupImporterProvider).import(backup);
      if (!mounted) return;
      ref
        ..invalidate(coursesProvider)
        ..invalidate(appSettingsProvider);
      setState(() {
        _writing = false;
        _message = 'Restored $summary.';
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _writing = false;
        // Stated honestly: a failure part-way through leaves what it already
        // wrote. Claiming otherwise would be worse than the limitation.
        _error =
            'The restore stopped part-way through. Anything it added '
            'before stopping is still present.\n\n$e';
      });
    }
  }

  /// Asks for a path, since the app has no file picker on Android without an
  /// extra plugin, and exports already print the path they wrote.
  Future<String?> _askForPath() {
    return ref.read(backupFilesProvider).defaultDirectory().then((directory) {
      if (!mounted) return null;

      // The dialog owns its own controller. Disposing one from the caller after
      // `showDialog` returns is too early: the route is still tearing down and
      // its TextField still depends on the controller, which throws
      // `_dependents.isEmpty` in the framework.
      return showDialog<String>(
        context: context,
        builder: (context) => _PathPrompt(initialDirectory: directory),
      );
    });
  }

  Future<bool?> _confirm(Backup backup) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text(
          'It holds ${backup.courses.length} '
          '${backup.courses.length == 1 ? 'course' : 'courses'} and '
          '${backup.cardCount} '
          '${backup.cardCount == 1 ? 'card' : 'cards'}.\n\n'
          'They will be ADDED to this device. Nothing you already have is '
          'deleted or changed, so restoring the same file twice gives you two '
          'copies.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const new({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = isError
        ? scheme.errorContainer
        : scheme.secondaryContainer;
    final foreground = isError
        ? scheme.onErrorContainer
        : scheme.onSecondaryContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(message, style: TextStyle(color: foreground)),
    );
  }
}

/// The path prompt, as a stateful widget so it can own its controller.
///
/// A separate widget rather than an inline closure because the controller's
/// lifetime must match the dialog's: it has to survive until the route is
/// fully disposed, which a caller holding it across `await showDialog` cannot
/// arrange.
class _PathPrompt extends StatefulWidget {
  const new({required this.initialDirectory});

  final String initialDirectory;

  @override
  State<_PathPrompt> createState() => _PathPromptState();
}

class _PathPromptState extends State<_PathPrompt> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.initialDirectory}/');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Restore from a file'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Enter the full path of the backup file. Every backup this app '
            'writes lands in this folder:',
          ),
          const SizedBox(height: 12),
          SelectableText(
            widget.initialDirectory,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Backup file path',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Open'),
        ),
      ],
    );
  }
}
