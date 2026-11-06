import 'package:flutter_test/flutter_test.dart';
import 'package:qab_windows_checklist/task_model.dart';

Task task(
  String id,
  String title, {
  bool done = false,
  TaskPriority priority = TaskPriority.normal,
  int createdAt = 1,
}) =>
    Task(id: id, title: title, done: done, priority: priority, createdAt: createdAt);

String repeat(String value, int count) => List<String>.filled(count, value).join();

void main() {
  group('validateTitle', () {
    test('rejects blank input with guidance', () {
      final result = validateTitle('   ');
      expect(result.isValid, isFalse);
      expect(result.error, 'Enter a task title before adding it.');
    });

    test('rejects null input', () {
      expect(validateTitle(null).isValid, isFalse);
    });

    test('trims and collapses inner whitespace', () {
      final result = validateTitle('  Review    the   PR ');
      expect(result.isValid, isTrue);
      expect(result.value, 'Review the PR');
    });

    test('enforces the 120 character limit', () {
      expect(validateTitle(repeat('a', 120)).isValid, isTrue);
      final tooLong = validateTitle(repeat('b', 121));
      expect(tooLong.isValid, isFalse);
      expect(tooLong.error, contains('120'));
      expect(tooLong.error, contains('121'));
    });

    test('accepts unicode titles', () {
      expect(validateTitle('مراجعة — 審査 ✅').value, 'مراجعة — 審査 ✅');
    });
  });

  group('ordering and summary', () {
    test('incomplete first, then priority, then age', () {
      final ordered = sortedForDisplay(<Task>[
        task('a', 'Done urgent', done: true, priority: TaskPriority.high, createdAt: 1),
        task('b', 'Low pending', priority: TaskPriority.low, createdAt: 2),
        task('c', 'High newer', priority: TaskPriority.high, createdAt: 9),
        task('d', 'High older', priority: TaskPriority.high, createdAt: 3),
      ]);
      expect(ordered.map((item) => item.id).toList(), <String>['d', 'c', 'b', 'a']);
    });

    test('summary computes counts and percent', () {
      final summary = summarize(<Task>[
        task('a', 'A', done: true),
        task('b', 'B'),
        task('c', 'C'),
        task('d', 'D'),
      ]);
      expect(summary.total, 4);
      expect(summary.done, 1);
      expect(summary.remaining, 3);
      expect(summary.percent, 25);
      expect(summary.headline, '1 of 4 done');
    });

    test('empty and complete summaries', () {
      expect(summarize(<Task>[]).headline, 'No tasks yet');
      expect(summarize(<Task>[]).percent, 0);
      final complete = summarize(<Task>[
        task('a', 'A', done: true),
        task('b', 'B', done: true),
      ]);
      expect(complete.percent, 100);
      expect(complete.headline, 'All 2 done');
    });

    test('percent truncates for thirds', () {
      final summary = summarize(<Task>[
        task('a', 'A', done: true),
        task('b', 'B'),
        task('c', 'C'),
      ]);
      expect(summary.percent, 33);
    });
  });

  group('appendTask', () {
    test('appends a unique id for the same millisecond', () {
      final first = appendTask(<Task>[], 'One', TaskPriority.normal, 42);
      final second = appendTask(first, 'Two', TaskPriority.low, 42);
      expect(second.length, 2);
      expect(second.first.id, 't42');
      expect(second.last.id, isNot('t42'));
      expect(second.last.priority, TaskPriority.low);
    });
  });

  group('codec', () {
    test('round trips every field', () {
      final original = <Task>[
        task('t1', 'Quotes "here" and \\ backslash and \n newline',
            done: true, priority: TaskPriority.high, createdAt: 111),
        task('t2', 'مراجعة — 審査 ✅', priority: TaskPriority.low, createdAt: 222),
      ];
      final decoded = decodeTasks(encodeTasks(original));
      expect(decoded.formatOk, isTrue);
      expect(decoded.skippedLines, 0);
      expect(decoded.tasks, original);
      expect(decoded.needsRecoveryCopy, isFalse);
    });

    test('blank payload is an empty checklist', () {
      expect(decodeTasks(null).formatOk, isTrue);
      expect(decodeTasks('   ').tasks, isEmpty);
    });

    test('unknown header is refused', () {
      final decoded = decodeTasks('not our format');
      expect(decoded.formatOk, isFalse);
      expect(decoded.tasks, isEmpty);
      expect(decoded.needsRecoveryCopy, isTrue);
    });

    test('future schema is refused', () {
      expect(decodeTasks('{"app":"qab-task-utility","schema":2}').formatOk, isFalse);
    });

    test('damaged lines are skipped and good tasks survive', () {
      final payload = '${encodeTasks(<Task>[task('t1', 'Survivor', priority: TaskPriority.high, createdAt: 9)])}'
          '\n{"broken":'
          '\n{"id":"t9","title":"   ","done":false,"priority":"high","createdAt":1}';
      final decoded = decodeTasks(payload);
      expect(decoded.formatOk, isTrue);
      expect(decoded.tasks.length, 1);
      expect(decoded.tasks.first.title, 'Survivor');
      expect(decoded.skippedLines, 2);
    });

    test('priority parsing falls back to normal', () {
      expect(TaskPriority.parse(' HIGH '), TaskPriority.high);
      expect(TaskPriority.parse('urgent'), TaskPriority.normal);
      expect(TaskPriority.parse(null), TaskPriority.normal);
      expect(TaskPriority.values.map((item) => item.label).toList(), <String>['High', 'Normal', 'Low']);
    });
  });
}
