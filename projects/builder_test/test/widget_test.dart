import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:builder_test/main.dart';

void main() {
  testWidgets('starts at zero', (WidgetTester tester) async {
    await tester.pumpWidget(const BuilderTestApp());

    expect(find.text('Builder Test'), findsOneWidget);
    expect(find.text('Current count'), findsOneWidget);
    expect(find.byKey(const Key('counter_value')), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('increment increases the counter by one per tap',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BuilderTestApp());

    await tester.tap(find.text('Increment'));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsNothing);

    await tester.tap(find.text('Increment'));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.text('Increment'));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('counter_value'))).data,
      '3',
    );
  });

  testWidgets('reset returns the counter to zero', (WidgetTester tester) async {
    await tester.pumpWidget(const BuilderTestApp());

    await tester.tap(find.text('Increment'));
    await tester.pump();
    await tester.tap(find.text('Increment'));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(find.text('0'), findsOneWidget);
    expect(find.text('2'), findsNothing);
  });

  testWidgets('reset while already zero keeps the counter at zero',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BuilderTestApp());

    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(find.text('0'), findsOneWidget);
  });
}
