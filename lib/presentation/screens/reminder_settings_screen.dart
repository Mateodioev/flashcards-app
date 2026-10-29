import 'package:flashcards2/data/notifications/reminder_settings_link.dart';
import 'package:flashcards2/domain/reminders/notification_gateway.dart';
import 'package:flashcards2/domain/reminders/reminder.dart';
import 'package:flashcards2/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Plan D5: new reminders default to 18:00 local, user-editable.
const defaultReminderTime = TimeOfDay(hour: 18, minute: 0);

/// The D4 "Reminders" area: every subscription, its time-of-day and enable
/// switch, plus the access banner from T5 when the OS cannot deliver
/// reminders. Add/edit goes through one editor sheet; saving always goes
/// through `saveReminderProvider` so the permission flow (S10) and the
/// reconcile-from-database rule (S1) are never bypassed.
class ReminderSettingsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptions = ref.watch(reminderSubscriptionsProvider);
    final access = ref.watch(reminderAccessProvider);
    final targets = ref.watch(reminderTargetsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref, subscriptions.value ?? []),
        icon: const Icon(Icons.add),
        label: const Text('Add reminder'),
      ),
      body: Column(
        children: <Widget>[
          _AccessBanner(access: access.value),
          Expanded(
            child: subscriptions.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text('Could not load reminders.'),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () =>
                          ref.invalidate(reminderSubscriptionsProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (rows) => rows.isEmpty
                  ? _EmptyReminders(
                      onAdd: () => _openEditor(context, ref, rows),
                    )
                  : ListView(
                      children: <Widget>[
                        for (final row in rows)
                          _ReminderRow(
                            subscription: row,
                            targets: targets.value,
                            onToggle: (enabled) =>
                                _toggle(ref, context, row, enabled),
                            onDelete: () => _confirmDelete(context, ref, row),
                            onTap: () => _openEditor(context, ref, rows, row),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(
    WidgetRef ref,
    BuildContext context,
    ReminderSubscription subscription,
    bool enabled,
  ) async {
    final result = await ref.read(saveReminderProvider)(
      subscription.copyWith(enabled: enabled),
    );
    ref.invalidate(reminderAccessProvider);
    if (!context.mounted) return;
    _explainDenial(context, enabled: enabled, access: result.access);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ReminderSubscription subscription,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this reminder?'),
        content: Text(
          'The ${_targetName(subscription, null)} reminder will no longer '
          'fire.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(deleteReminderProvider)(subscription.id);
    }
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    List<ReminderSubscription> subscriptions, [
    ReminderSubscription? existing,
  ]) async {
    final access = await showModalBottomSheet<ReminderAccess?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReminderEditorSheet(
        existing: existing,
        subscriptions: subscriptions,
      ),
    );
    if (!context.mounted) return;
    _explainDenial(context, enabled: true, access: access);
  }

  /// T5/S10, visible part: when the OS cannot deliver, the save flow has
  /// already stored the subscription disabled so nothing is lost — here the
  /// user is told that and offered the only recovery path, the settings
  /// deep-link.
  static void _explainDenial(
    BuildContext context, {
    required bool enabled,
    required ReminderAccess? access,
  }) {
    if (!enabled || access == null || access == ReminderAccess.granted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'The reminder was saved turned off — notifications are '
          'unavailable on this device.',
        ),
        action: SnackBarAction(
          label: 'Open notification settings',
          onPressed: openNotificationSettingsForReminders,
        ),
      ),
    );
  }
}

/// Picks the string the row and the delete dialog show for a target. Global
/// is "Everything"; archived courses keep their reminder listed but marked
/// (plan §7 default).
String _targetName(ReminderSubscription sub, ReminderTargets? targets) {
  switch (sub.scope) {
    case ReminderScope.global:
      return 'Everything';
    case ReminderScope.course:
      final target = targets?.courses[sub.targetId];
      if (target == null) return 'Course #${sub.targetId}';
      return target.archived ? '${target.name} (archived)' : target.name;
    case ReminderScope.theme:
      final themes = targets?.themes ?? const <ThemeTarget>[];
      for (final theme in themes) {
        if (theme.id == sub.targetId) {
          return theme.archived
              ? '${theme.name} (${theme.courseName} — archived)'
              : '${theme.name} (${theme.courseName})';
        }
      }
      return 'Theme #${sub.targetId}';
  }
}

String _formatClock(int hour, int minute) {
  return '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';
}

/// The empty state explains what a reminder is and offers the same entry
/// point as the FAB, one tap away instead of a dead-end label.
class _EmptyReminders extends StatelessWidget {
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
              Icons.alarm_add_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No reminders yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Get a daily nudge to review: everything at once, one course, '
              'or one theme.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: onAdd,
              child: const Text('Add your first reminder'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const new({
    required this.subscription,
    required this.targets,
    required this.onToggle,
    required this.onDelete,
    required this.onTap,
  });

  final ReminderSubscription subscription;
  final ReminderTargets? targets;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(_targetName(subscription, targets)),
      subtitle: Text(
        'Daily at ${_formatClock(subscription.hour, subscription.minute)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Switch(value: subscription.enabled, onChanged: onToggle),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete reminder',
            onPressed: onDelete,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// The T5 banner: visible whenever the OS cannot deliver reminders, because
/// neither remediation (re-asking the runtime permission, re-enabling the
/// muted channel) is possible in-app — the deep-link is the only recovery.
class _AccessBanner extends StatelessWidget {
  const new({required this.access});

  final ReminderAccess? access;

  @override
  Widget build(BuildContext context) {
    final current = access;
    if (current == null || current == ReminderAccess.granted) {
      return const SizedBox.shrink();
    }
    final message = switch (current) {
      ReminderAccess.permissionDenied =>
        'Notifications are turned off, so your reminders will not fire.',
      ReminderAccess.channelDisabled =>
        'The Study reminders channel is muted, so your reminders will not '
            'fire.',
      ReminderAccess.granted => '',
    };
    return MaterialBanner(
      content: Text(message),
      actions: const <Widget>[
        TextButton(
          onPressed: openNotificationSettingsForReminders,
          child: Text('Open notification settings'),
        ),
      ],
    );
  }
}

/// Add/edit sheet for one subscription. Enforces S2 one-per-target in add
/// mode by listing only targets that have no reminder yet (a target with a
/// reminder is edited via its own row instead); an edit keeps its target
/// fixed — plan §2: "a target with a reminder shows 'edit', not 'add'".
/// Pops with the final access state so the screen can explain a denial.
class ReminderEditorSheet extends ConsumerStatefulWidget {
  const new({
    required this.subscriptions,
    this.existing,
    super.key,
  });

  final List<ReminderSubscription> subscriptions;
  final ReminderSubscription? existing;

  @override
  ConsumerState<ReminderEditorSheet> createState() =>
      _ReminderEditorSheetState();
}

class _ReminderEditorSheetState extends ConsumerState<ReminderEditorSheet> {
  late ReminderScope _scope = widget.existing?.scope ?? ReminderScope.global;
  late TimeOfDay _time = widget.existing == null
      ? defaultReminderTime
      : TimeOfDay(
          hour: widget.existing!.hour,
          minute: widget.existing!.minute,
        );
  late bool _enabled = widget.existing?.enabled ?? true;
  int? _selectedCourseId;
  int? _selectedThemeId;

  bool get _isEditing => widget.existing != null;

  /// Course ids (or theme ids) that already have a reminder; add mode must
  /// not offer them (S2). Locking edit mode to its own target makes the
  /// same rule hold there.
  Set<int> _takenTargets(ReminderScope scope) {
    return {
      for (final sub in widget.subscriptions)
        if (sub.scope == scope && sub.targetId != null) sub.targetId!,
    };
  }

  bool get _hasGlobal => widget.subscriptions.any(
        (sub) => sub.scope == ReminderScope.global,
      );

  int? get _targetId {
    if (_isEditing) return widget.existing!.targetId;
    return switch (_scope) {
      ReminderScope.global => null,
      ReminderScope.course => _selectedCourseId,
      ReminderScope.theme => _selectedThemeId,
    };
  }

  bool get _canSave {
    if (_isEditing) return true;
    return switch (_scope) {
      ReminderScope.global => !_hasGlobal,
      ReminderScope.course => _selectedCourseId != null,
      ReminderScope.theme => _selectedThemeId != null,
    };
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (picked != null) {
      setState(() => _time = picked);
    }
  }

  Future<void> _save() async {
    final base = widget.existing;
    final draft = base == null
        ? ReminderSubscription(
            scope: _scope,
            targetId: _targetId,
            hour: _time.hour,
            minute: _time.minute,
            enabled: _enabled,
          )
        : ReminderSubscription(
            id: base.id,
            scope: base.scope,
            targetId: base.targetId,
            hour: _time.hour,
            minute: _time.minute,
            enabled: _enabled,
          );
    final result = await ref.read(saveReminderProvider)(draft);
    ref.invalidate(reminderAccessProvider);
    if (mounted) {
      Navigator.of(context).pop(result.access);
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets = ref.watch(reminderTargetsProvider).value;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              _isEditing ? 'Edit reminder' : 'Add reminder',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (_isEditing)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Target'),
                subtitle: Text(
                  _targetName(widget.existing!, targets),
                ),
              )
            else ...<Widget>[
              SegmentedButton<ReminderScope>(
                segments: const <ButtonSegment<ReminderScope>>[
                  ButtonSegment(
                    value: ReminderScope.global,
                    label: Text('Everything'),
                  ),
                  ButtonSegment(
                    value: ReminderScope.course,
                    label: Text('Course'),
                  ),
                  ButtonSegment(
                    value: ReminderScope.theme,
                    label: Text('Theme'),
                  ),
                ],
                selected: <ReminderScope>{_scope},
                onSelectionChanged: (selection) {
                  setState(() => _scope = selection.first);
                },
              ),
              const SizedBox(height: 8),
              _ScopePicker(
                scope: _scope,
                targets: targets,
                takenCourses: _takenTargets(ReminderScope.course),
                takenThemes: _takenTargets(ReminderScope.theme),
                hasGlobal: _hasGlobal,
                selectedCourseId: _selectedCourseId,
                selectedThemeId: _selectedThemeId,
                onCourseChanged: (id) =>
                    setState(() => _selectedCourseId = id),
                onThemeChanged: (id) => setState(() => _selectedThemeId = id),
              ),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Time'),
              subtitle: Text(_formatClock(_time.hour, _time.minute)),
              onTap: _pickTime,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enabled'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _canSave ? _save : null,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The per-scope target picker for add mode: a course dropdown, or a theme
/// dropdown whose entries group each theme under its course name (D4). The
/// global scope needs no target; if "Everything" already has a reminder the
/// hint explains why Save is unavailable (S2).
class _ScopePicker extends StatelessWidget {
  const new({
    required this.scope,
    required this.targets,
    required this.takenCourses,
    required this.takenThemes,
    required this.hasGlobal,
    required this.selectedCourseId,
    required this.selectedThemeId,
    required this.onCourseChanged,
    required this.onThemeChanged,
  });

  final ReminderScope scope;
  final ReminderTargets? targets;
  final Set<int> takenCourses;
  final Set<int> takenThemes;
  final bool hasGlobal;
  final int? selectedCourseId;
  final int? selectedThemeId;
  final ValueChanged<int?> onCourseChanged;
  final ValueChanged<int?> onThemeChanged;

  @override
  Widget build(BuildContext context) {
    switch (scope) {
      case ReminderScope.global:
        if (hasGlobal) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '"Everything" already has a reminder — tap its row to edit it.',
            ),
          );
        }
        return const SizedBox.shrink();
      case ReminderScope.course:
        final courses = (targets?.courses.entries ?? const Iterable.empty())
            .where((entry) => !takenCourses.contains(entry.key))
            .toList();
        return DropdownMenu<int>(
          label: const Text('Course'),
          initialSelection: selectedCourseId,
          dropdownMenuEntries: <DropdownMenuEntry<int>>[
            for (final entry in courses)
              DropdownMenuEntry(
                value: entry.key,
                label: entry.value.archived
                    ? '${entry.value.name} (archived)'
                    : entry.value.name,
              ),
          ],
          onSelected: onCourseChanged,
        );
      case ReminderScope.theme:
        final themes = (targets?.themes ?? const <ThemeTarget>[])
            .where((theme) => !takenThemes.contains(theme.id))
            .toList();
        return DropdownMenu<int>(
          label: const Text('Theme'),
          initialSelection: selectedThemeId,
          dropdownMenuEntries: <DropdownMenuEntry<int>>[
            for (final theme in themes)
              DropdownMenuEntry(
                value: theme.id,
                label: theme.archived
                    ? '${theme.courseName} · ${theme.name} (archived)'
                    : '${theme.courseName} · ${theme.name}',
              ),
          ],
          onSelected: onThemeChanged,
        );
    }
  }
}
