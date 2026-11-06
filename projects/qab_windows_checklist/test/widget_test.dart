import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qab_windows_checklist/main.dart';
import 'package:qab_windows_checklist/task_model.dart';
import 'package:qab_windows_checklist/task_storage.dart';

Task sample(String id, String title, {bool done = false, TaskPriority priority = TaskPriority.normal, int createdAt = 1}) =>
    Task(id: id, title: title, done: done, priority: priority, createdAt: createdAt);

void main() {
  testWidgets('shows empty state and a disabled clear button', (tester) async {
    final storage = MemoryTaskStorage();
    await tester.pumpWidget(QaTaskApp(storage: storage));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('emptyState')), findsOneWidget);
    expect(find.text('No tasks yet'), findsOneWidget);

    final clear = tester.widget<OutlinedButton>(find.byKey(const Key('clearButton')));
    expect(clear.onPressed, isNull);
  });

  testWidgets('rejects a blank title with a visible error', (tester) async {
    final storage = MemoryTaskStorage();
    await tester.pumpWidget(QaTaskApp(storage: storage));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('titleField')), '   ');
    await tester.tap(find.byKey(const Key('addButton')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a task title before adding it.'), findsOneWidget);
    expect(storage.tasks, isEmpty);
    expect(find.byKey(const Key('emptyState')), findsOneWidget);
  });

  testWidgets('adds a task through the UI and persists it', (tester) async {
    final storage = MemoryTaskStorage();
    await tester.pumpWidget(QaTaskApp(storage: storage));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('priority-high')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('titleField')), 'Ship acceptance report');
    await tester.tap(find.byKey(const Key('addButton')));
    await tester.pumpAndSettle();

    expect(find.text('Ship acceptance report'), findsOneWidget);
    expect(find.byKey(const Key('emptyState')), findsNothing);
    expect(find.text('0 of 1 done'), findsOneWidget);
    expect(storage.saved, isTrue);
    expect(storage.tasks.length, 1);
    expect(storage.tasks.first.priority, TaskPriority.high);
    expect(find.textContaining('Added'), findsOneWidget);
  });

  testWidgets('toggles a task, updates the summary and clears completed', (tester) async {
    final storage = MemoryTaskStorage(tasks: <Task>[
      sample('t1', 'One'),
      sample('t2', 'Two', priority: TaskPriority.low, createdAt: 2),
    ]);
    await tester.pumpWidget(QaTaskApp(storage: storage));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('toggle-t1')));
    await tester.pumpAndSettle();

    expect(find.text('1 of 2 done'), findsOneWidget);
    expect(storage.tasks.firstWhere((task) => task.id == 't1').done, isTrue);

    await tester.ensureVisible(find.byKey(const Key('clearButton')));
    await tester.tap(find.byKey(const Key('clearButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-t1')), findsNothing);
    expect(find.byKey(const Key('task-t2')), findsOneWidget);
    expect(find.text('0 of 1 done'), findsOneWidget);
  });

  testWidgets('deletes a single task', (tester) async {
    final storage = MemoryTaskStorage(tasks: <Task>[sample('t1', 'Only task')]);
    await tester.pumpWidget(QaTaskApp(storage: storage));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('delete-t1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-t1')), findsNothing);
    expect(find.byKey(const Key('emptyState')), findsOneWidget);
    expect(storage.tasks, isEmpty);
  });

  testWidgets('surfaces a recovery notice from storage', (tester) async {
    final storage = MemoryTaskStorage(
      loadNotice: 'Recovered the checklist and skipped 1 damaged entry.',
    );
    await tester.pumpWidget(QaTaskApp(storage: storage));
    await tester.pumpAndSettle();

    expect(find.text('Recovered the checklist and skipped 1 damaged entry.'), findsOneWidget);
  });

  testWidgets('restores a recovery copy through the UI', (tester) async {
    final storage = MemoryTaskStorage(
      recoveryTasks: <Task>[sample('r1', 'Recovered task')],
    );
    await tester.pumpWidget(QaTaskApp(storage: storage));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recoveryButton')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('recoveryButton')));
    await tester.tap(find.byKey(const Key('recoveryButton')));
    await tester.pumpAndSettle();

    expect(find.text('Recovered task'), findsOneWidget);
    expect(storage.tasks.length, 1);
    expect(find.byKey(const Key('recoveryButton')), findsNothing);
  });

  testWidgets('cycles the appearance mode', (tester) async {
    await tester.pumpWidget(QaTaskApp(storage: MemoryTaskStorage()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.brightness_auto), findsOneWidget);

    await tester.tap(find.byKey(const Key('themeToggle')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.light_mode), findsOneWidget);

    await tester.tap(find.byKey(const Key('themeToggle')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.dark_mode), findsOneWidget);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });
}
