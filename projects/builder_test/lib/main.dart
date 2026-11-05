import 'package:flutter/material.dart';

void main() {
  runApp(const BuilderTestApp());
}

/// Root widget for the Builder Test counter app.
class BuilderTestApp extends StatelessWidget {
  const BuilderTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Builder Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      home: const CounterPage(),
    );
  }
}

/// Increment / reset counter screen.
class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  int _count = 0;

  void _increment() {
    setState(() {
      _count += 1;
    });
  }

  void _reset() {
    setState(() {
      _count = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Builder Test'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('Current count'),
            const SizedBox(height: 8),
            Text(
              '$_count',
              key: const Key('counter_value'),
              style: Theme.of(context).textTheme.displayMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _increment,
              child: const Text('Increment'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _reset,
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }
}
