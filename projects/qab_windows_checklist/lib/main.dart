import 'package:flutter/material.dart';

import 'task_model.dart';
import 'task_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await FileTaskStorage.open();
  runApp(QaTaskApp(storage: storage));
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF2F5FE0), brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    visualDensity: VisualDensity.standard,
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}

IconData themeModeIcon(ThemeMode mode) {
  if (mode == ThemeMode.light) return Icons.light_mode;
  if (mode == ThemeMode.dark) return Icons.dark_mode;
  return Icons.brightness_auto;
}

String themeModeLabel(ThemeMode mode) {
  if (mode == ThemeMode.light) return 'Light';
  if (mode == ThemeMode.dark) return 'Dark';
  return 'System';
}

class QaTaskApp extends StatefulWidget {
  const QaTaskApp({super.key, required this.storage});

  final TaskStorage storage;

  @override
  State<QaTaskApp> createState() => _QaTaskAppState();
}

class _QaTaskAppState extends State<QaTaskApp> {
  ThemeMode _mode = ThemeMode.system;

  void _cycleTheme() {
    setState(() {
      if (_mode == ThemeMode.system) {
        _mode = ThemeMode.light;
      } else if (_mode == ThemeMode.light) {
        _mode = ThemeMode.dark;
      } else {
        _mode = ThemeMode.system;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QA Task Utility',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _mode,
      home: TaskHomePage(
        storage: widget.storage,
        themeMode: _mode,
        onCycleTheme: _cycleTheme,
      ),
    );
  }
}

class TaskHomePage extends StatefulWidget {
  const TaskHomePage({
    super.key,
    required this.storage,
    required this.themeMode,
    required this.onCycleTheme,
  });

  final TaskStorage storage;
  final ThemeMode themeMode;
  final VoidCallback onCycleTheme;

  @override
  State<TaskHomePage> createState() => _TaskHomePageState();
}

class _TaskHomePageState extends State<TaskHomePage> {
  final TextEditingController _controller = TextEditingController();
  List<Task> _tasks = const <Task>[];
  TaskPriority _priority = TaskPriority.normal;
  String? _error;
  String _status = '';
  bool _loading = true;
  bool _hasRecovery = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await widget.storage.load();
    if (!mounted) return;
    setState(() {
      _tasks = result.tasks;
      _loading = false;
      _hasRecovery = widget.storage.hasRecoveryCopy;
      final notice = result.notice;
      if (notice != null) _status = notice;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final validation = validateTitle(_controller.text);
    if (!validation.isValid) {
      setState(() => _error = validation.error);
      return;
    }
    final title = validation.value!;
    final updated = appendTask(
      _tasks,
      title,
      _priority,
      DateTime.now().millisecondsSinceEpoch,
    );
    setState(() {
      _tasks = updated;
      _controller.clear();
      _error = null;
      _status = 'Added “$title” as ${_priority.label} priority.';
    });
    await widget.storage.save(_tasks);
  }

  Future<void> _toggle(String id, bool done) async {
    final target = _tasks.where((task) => task.id == id).toList();
    if (target.isEmpty) return;
    setState(() {
      _tasks = [for (final task in _tasks) task.id == id ? task.copyWith(done: done) : task];
      _status = done ? 'Completed “${target.first.title}”.' : 'Reopened “${target.first.title}”.';
    });
    await widget.storage.save(_tasks);
  }

  Future<void> _delete(String id) async {
    final target = _tasks.where((task) => task.id == id).toList();
    if (target.isEmpty) return;
    setState(() {
      _tasks = _tasks.where((task) => task.id != id).toList();
      _status = 'Deleted “${target.first.title}”.';
    });
    await widget.storage.save(_tasks);
  }

  Future<void> _clearCompleted() async {
    final removed = _tasks.where((task) => task.done).length;
    if (removed == 0) {
      setState(() => _status = 'No completed tasks to clear.');
      return;
    }
    setState(() {
      _tasks = _tasks.where((task) => !task.done).toList();
      final label = removed == 1 ? 'task' : 'tasks';
      _status = 'Cleared $removed completed $label.';
    });
    await widget.storage.save(_tasks);
  }

  Future<void> _restoreRecovery() async {
    final result = await widget.storage.restoreRecovery();
    if (!mounted) return;
    setState(() {
      if (result.tasks.isNotEmpty) _tasks = result.tasks;
      _hasRecovery = widget.storage.hasRecoveryCopy;
      _status = result.notice ?? 'Recovery copy restored.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = summarize(_tasks);
    final ordered = sortedForDisplay(_tasks);

    return Scaffold(
      appBar: AppBar(
        title: const Text('QA Task Utility'),
        actions: <Widget>[
          IconButton(
            key: const Key('themeToggle'),
            tooltip: 'Appearance: ${themeModeLabel(widget.themeMode)}. Tap to change.',
            onPressed: widget.onCycleTheme,
            icon: Icon(themeModeIcon(widget.themeMode)),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                    children: <Widget>[
                      Text('QA Task Utility', style: theme.textTheme.headlineMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Local-only task utility · v1.0.0 · nothing leaves this device',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        summary.headline,
                        key: const Key('summary'),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: summary.percent / 100, minHeight: 8),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: TextField(
                              key: const Key('titleField'),
                              controller: _controller,
                              maxLength: 200,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _add(),
                              decoration: InputDecoration(
                                labelText: 'New task title',
                                errorText: _error,
                                counterText: '',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: ElevatedButton(
                              key: const Key('addButton'),
                              onPressed: _add,
                              style: ElevatedButton.styleFrom(minimumSize: const Size(96, 48)),
                              child: const Text('Add task'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('Priority', style: theme.textTheme.labelMedium),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: <Widget>[
                          for (final priority in TaskPriority.values)
                            ChoiceChip(
                              key: Key('priority-${priority.name}'),
                              label: Text(priority.label),
                              selected: _priority == priority,
                              onSelected: (_) => setState(() => _priority = priority),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (ordered.isEmpty)
                        Container(
                          key: const Key('emptyState'),
                          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            border: Border.all(color: theme.dividerColor),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            'No tasks yet.\nAdd your first task above. Incomplete tasks stay on top, highest priority first.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                        )
                      else
                        for (final task in ordered) _buildRow(task),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        key: const Key('clearButton'),
                        onPressed: summary.done == 0 ? null : _clearCompleted,
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        child: const Text('Clear completed'),
                      ),
                      if (_hasRecovery) ...<Widget>[
                        const SizedBox(height: 8),
                        OutlinedButton(
                          key: const Key('recoveryButton'),
                          onPressed: _restoreRecovery,
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                          child: const Text('Restore recovery copy'),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _status,
                          key: const Key('status'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildRow(Task task) {
    final theme = Theme.of(context);
    return Container(
      key: Key('task-${task.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Checkbox(
            key: Key('toggle-${task.id}'),
            value: task.done,
            onChanged: (value) => _toggle(task.id, value ?? false),
          ),
          Expanded(
            child: Text(
              task.title,
              key: Key('title-${task.id}'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                decoration: task.done ? TextDecoration.lineThrough : null,
                color: task.done ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.primary),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(task.priority.label, style: theme.textTheme.labelSmall),
          ),
          IconButton(
            key: Key('delete-${task.id}'),
            tooltip: 'Delete ${task.title}',
            onPressed: () => _delete(task.id),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}
