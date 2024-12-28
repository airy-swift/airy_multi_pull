import 'package:airy_multi_pull/airy_multi_pull.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

final firstKey = GlobalKey();
final secondKey = GlobalKey();
final thirdKey = GlobalKey();
final fourthKey = GlobalKey();
final fifthKey = GlobalKey();

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: AiryMultiPull(
        customIndicators: [
          PullTarget(
            key: firstKey,
            onPull: () async {
              await Future<void>.delayed(const Duration(seconds: 2));
              print('First');
            },
            child: Icon(Icons.add),
          ),
          PullTarget(
            key: secondKey,
            onPull: () {
              print('Second');
            },
            child: Icon(Icons.refresh),
          ),
          PullTarget(
            key: thirdKey,
            onPull: () {
              print('Third');
            },
            child: Icon(Icons.delete),
          ),
          PullTarget(
            key: fourthKey,
            onPull: () async {
              print('Fourth');
            },
            child: Icon(Icons.refresh),
          ),
          PullTarget(
            key: fifthKey,
            onPull: () async {
              print('Fifth');
            },
            child: Icon(Icons.delete),
          ),
        ],
        dragRatio: 1,
        child: ListView.builder(
          itemCount: 1000,
          itemBuilder: (context, index) {
            return ListTile(
              title: Text('Item $index'),
            );
          },
        ),
      ),
    );
  }
}
