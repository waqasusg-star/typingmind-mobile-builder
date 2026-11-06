import 'dart:io';

import 'task_model.dart';

class TaskLoad {
  const TaskLoad(this.tasks, {this.notice});

  final List<Task> tasks;
  final String? notice;
}

/// Storage seam so widget tests never touch the real file system.
abstract class TaskStorage {
  Future<TaskLoad> load();

  Future<void> save(List<Task> tasks);

  bool get hasRecoveryCopy;

  Future<TaskLoad> restoreRecovery();
}

class MemoryTaskStorage implements TaskStorage {
  MemoryTaskStorage({List<Task> tasks = const <Task>[], this.loadNotice, this.recoveryTasks})
      : _tasks = List<Task>.of(tasks);

  List<Task> _tasks;
  final String? loadNotice;
  List<Task>? recoveryTasks;
  bool saved = false;

  List<Task> get tasks => List<Task>.unmodifiable(_tasks);

  @override
  bool get hasRecoveryCopy => recoveryTasks != null;

  @override
  Future<TaskLoad> load() async => TaskLoad(List<Task>.of(_tasks), notice: loadNotice);

  @override
  Future<void> save(List<Task> tasks) async {
    _tasks = List<Task>.of(tasks);
    saved = true;
  }

  @override
  Future<TaskLoad> restoreRecovery() async {
    final restored = recoveryTasks;
    if (restored == null) {
      return const TaskLoad(<Task>[], notice: 'There is no recovery copy to restore.');
    }
    recoveryTasks = null;
    _tasks = List<Task>.of(restored);
    final label = restored.length == 1 ? 'task' : 'tasks';
    return TaskLoad(
      List<Task>.of(restored),
      notice: 'Restored ${restored.length} $label from the recovery copy.',
    );
  }
}

/// Windows-first file storage: %APPDATA%\QaTaskUtility, temp directory as fallback.
/// Writes go to a temporary file and are renamed, and unreadable payloads are kept
/// as a recovery copy instead of being destroyed.
class FileTaskStorage implements TaskStorage {
  FileTaskStorage._(this._file, this._recovery);

  final File _file;
  final File _recovery;

  static Future<FileTaskStorage> open() async {
    final appData = Platform.environment['APPDATA'];
    final base = (appData != null && appData.isNotEmpty) ? Directory(appData) : Directory.systemTemp;
    final separator = Platform.pathSeparator;
    final directory = Directory('${base.path}${separator}QaTaskUtility');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return FileTaskStorage._(
      File('${directory.path}${separator}tasks_v1.jsonl'),
      File('${directory.path}${separator}tasks_v1_recovery.jsonl'),
    );
  }

  @override
  bool get hasRecoveryCopy => _recovery.existsSync();

  @override
  Future<TaskLoad> load() async {
    if (!await _file.exists()) return const TaskLoad(<Task>[]);
    final payload = await _file.readAsString();
    final decoded = decodeTasks(payload);
    if (!decoded.formatOk) {
      await _recovery.writeAsString(payload, flush: true);
      await _file.delete();
      return const TaskLoad(
        <Task>[],
        notice:
            'The saved checklist could not be read, so a fresh list was started. The unreadable copy was kept for recovery.',
      );
    }
    if (decoded.skippedLines > 0) {
      await _recovery.writeAsString(payload, flush: true);
      final label = decoded.skippedLines == 1 ? 'entry' : 'entries';
      return TaskLoad(
        decoded.tasks,
        notice: 'Recovered the checklist and skipped ${decoded.skippedLines} damaged $label.',
      );
    }
    return TaskLoad(decoded.tasks);
  }

  @override
  Future<void> save(List<Task> tasks) async {
    final temp = File('${_file.path}.tmp');
    await temp.writeAsString(encodeTasks(tasks), flush: true);
    if (await _file.exists()) {
      await _file.delete();
    }
    await temp.rename(_file.path);
  }

  @override
  Future<TaskLoad> restoreRecovery() async {
    if (!await _recovery.exists()) {
      return const TaskLoad(<Task>[], notice: 'There is no recovery copy to restore.');
    }
    final payload = await _recovery.readAsString();
    final decoded = decodeTasks(payload);
    if (!decoded.formatOk || decoded.tasks.isEmpty) {
      return const TaskLoad(<Task>[], notice: 'The recovery copy is unreadable too, so nothing was restored.');
    }
    await save(decoded.tasks);
    await _recovery.delete();
    final label = decoded.tasks.length == 1 ? 'task' : 'tasks';
    return TaskLoad(
      decoded.tasks,
      notice: 'Restored ${decoded.tasks.length} $label from the recovery copy.',
    );
  }
}
