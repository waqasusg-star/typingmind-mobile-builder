import 'dart:convert';

/// Priority of a task. `rank` keeps ordering stable and testable.
enum TaskPriority {
  high('High', 0),
  normal('Normal', 1),
  low('Low', 2);

  const TaskPriority(this.label, this.rank);

  final String label;
  final int rank;

  static TaskPriority parse(String? raw) {
    final value = raw?.trim().toLowerCase();
    for (final priority in TaskPriority.values) {
      if (priority.name == value) return priority;
    }
    return TaskPriority.normal;
  }
}

class Task {
  const Task({
    required this.id,
    required this.title,
    required this.done,
    required this.priority,
    required this.createdAt,
  });

  final String id;
  final String title;
  final bool done;
  final TaskPriority priority;
  final int createdAt;

  Task copyWith({bool? done, String? title}) => Task(
        id: id,
        title: title ?? this.title,
        done: done ?? this.done,
        priority: priority,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'done': done,
        'priority': priority.name,
        'createdAt': createdAt,
      };

  static Task? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final done = json['done'];
    final createdAt = json['createdAt'];
    if (id is! String || title is! String || done is! bool || createdAt is! num) {
      return null;
    }
    return Task(
      id: id,
      title: title,
      done: done,
      priority: TaskPriority.parse(json['priority'] is String ? json['priority'] as String : null),
      createdAt: createdAt.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Task &&
      other.id == id &&
      other.title == title &&
      other.done == done &&
      other.priority == priority &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, title, done, priority, createdAt);
}

const int maxTitleLength = 120;
const String payloadHeader = '{"app":"qab-task-utility","schema":1}';

class TitleValidation {
  const TitleValidation.valid(this.value) : error = null;
  const TitleValidation.invalid(this.error) : value = null;

  final String? value;
  final String? error;

  bool get isValid => value != null;
}

/// Validates and normalises a title typed by the user.
TitleValidation validateTitle(String? raw) {
  final collapsed = (raw ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  if (collapsed.isEmpty) {
    return const TitleValidation.invalid('Enter a task title before adding it.');
  }
  if (collapsed.length > maxTitleLength) {
    return TitleValidation.invalid(
      'Keep the title to $maxTitleLength characters or fewer (currently ${collapsed.length}).',
    );
  }
  return TitleValidation.valid(collapsed);
}

List<Task> appendTask(List<Task> tasks, String title, TaskPriority priority, int now) {
  var suffix = 0;
  var candidate = 't$now';
  while (tasks.any((task) => task.id == candidate)) {
    suffix += 1;
    candidate = 't$now-$suffix';
  }
  return <Task>[
    ...tasks,
    Task(id: candidate, title: title, done: false, priority: priority, createdAt: now),
  ];
}

/// Incomplete first, then highest priority, then oldest, then alphabetical.
List<Task> sortedForDisplay(List<Task> tasks) {
  final copy = List<Task>.of(tasks);
  copy.sort((a, b) {
    if (a.done != b.done) return a.done ? 1 : -1;
    if (a.priority.rank != b.priority.rank) {
      return a.priority.rank.compareTo(b.priority.rank);
    }
    if (a.createdAt != b.createdAt) return a.createdAt.compareTo(b.createdAt);
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return copy;
}

class TaskSummary {
  const TaskSummary({
    required this.total,
    required this.done,
    required this.remaining,
    required this.percent,
    required this.headline,
  });

  final int total;
  final int done;
  final int remaining;
  final int percent;
  final String headline;
}

TaskSummary summarize(List<Task> tasks) {
  final total = tasks.length;
  final done = tasks.where((task) => task.done).length;
  final percent = total == 0 ? 0 : (done * 100) ~/ total;
  final headline = total == 0
      ? 'No tasks yet'
      : done == total
          ? 'All $total done'
          : '$done of $total done';
  return TaskSummary(
    total: total,
    done: done,
    remaining: total - done,
    percent: percent,
    headline: headline,
  );
}

class DecodeResult {
  const DecodeResult(this.tasks, this.skippedLines, this.formatOk);

  final List<Task> tasks;
  final int skippedLines;
  final bool formatOk;

  bool get needsRecoveryCopy => !formatOk || skippedLines > 0;
}

String encodeTasks(List<Task> tasks) {
  final buffer = StringBuffer(payloadHeader);
  for (final task in tasks) {
    buffer.write('\n');
    buffer.write(jsonEncode(task.toJson()));
  }
  return buffer.toString();
}

/// Header line plus one JSON object per item line. A damaged item line is skipped
/// instead of discarding the whole checklist. Stored titles are validated but kept
/// as saved (only outer whitespace is trimmed) so data round-trips exactly.
DecodeResult decodeTasks(String? payload) {
  final raw = payload ?? '';
  if (raw.trim().isEmpty) return const DecodeResult(<Task>[], 0, true);

  final lines = raw.split('\n').where((line) => line.trim().isNotEmpty).toList();
  if (lines.isEmpty) return const DecodeResult(<Task>[], 0, true);

  Object? header;
  try {
    header = jsonDecode(lines.first);
  } catch (_) {
    header = null;
  }
  final headerOk = header is Map && header['schema'] == 1;
  if (!headerOk) return const DecodeResult(<Task>[], 0, false);

  var skipped = 0;
  final tasks = <Task>[];
  for (final line in lines.skip(1)) {
    try {
      final decoded = jsonDecode(line);
      final task = decoded is Map<String, dynamic> ? Task.fromJson(decoded) : null;
      if (task == null) {
        skipped += 1;
        continue;
      }
      final trimmedTitle = task.title.trim();
      if (trimmedTitle.isEmpty || trimmedTitle.length > maxTitleLength) {
        skipped += 1;
        continue;
      }
      tasks.add(task.copyWith(title: trimmedTitle));
    } catch (_) {
      skipped += 1;
    }
  }
  return DecodeResult(tasks, skipped, true);
}
