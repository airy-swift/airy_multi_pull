import 'package:airy_multi_pull/airy_multi_pull.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

// プルダウン用のキー
final pullDownFirstKey = GlobalKey();
final pullDownSecondKey = GlobalKey();
final pullDownThirdKey = GlobalKey();

// プルアップ用のキー
final pullUpFirstKey = GlobalKey();
final pullUpSecondKey = GlobalKey();
final pullUpThirdKey = GlobalKey();

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: AiryMultiPull(
        onArmed: () async {
          HapticFeedback.mediumImpact();
          await Future<void>.delayed(const Duration(milliseconds: 130));
          HapticFeedback.lightImpact();
        },
        // プルダウン用のインジケータ（上部に表示）
        pullDownCustomIndicators: [
          PullTarget(
            key: pullDownFirstKey,
            onPull: () async {
              await Future<void>.delayed(const Duration(seconds: 1));
              debugPrint('🔵 プルダウン: 追加アクションが実行されました');
            },
            child: Icon(Icons.add, color: Colors.blue),
          ),
          PullTarget(
            key: pullDownSecondKey,
            onPull: () {
              debugPrint('🟢 プルダウン: 更新アクションが実行されました');
            },
            child: Icon(Icons.refresh, color: Colors.green),
          ),
          PullTarget(
            key: pullDownThirdKey,
            onPull: () {
              debugPrint('🟠 プルダウン: 設定アクションが実行されました');
            },
            child: Icon(Icons.settings, color: Colors.orange),
          ),
        ],
        // プルアップ用のインジケータ（下部に表示）
        pullUpCustomIndicators: [
          PullTarget(
            key: pullUpFirstKey,
            onPull: () async {
              await Future<void>.delayed(const Duration(seconds: 1));
              debugPrint('🔴 プルアップ: 削除アクションが実行されました');
            },
            child: Icon(Icons.delete, color: Colors.red),
          ),
          PullTarget(
            key: pullUpSecondKey,
            onPull: () {
              debugPrint('🩷 プルアップ: お気に入りアクションが実行されました');
            },
            child: Icon(Icons.favorite, color: Colors.pink),
          ),
          PullTarget(
            key: pullUpThirdKey,
            onPull: () {
              debugPrint('🟣 プルアップ: 共有アクションが実行されました');
            },
            child: Icon(Icons.share, color: Colors.purple),
          ),
        ],
        // プルダウン用のターゲットインジケータ
        pullDownTargetIndicator: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.blue.withAlpha(76),
            shape: BoxShape.circle,
          ),
        ),
        // プルアップ用のターゲットインジケータ
        pullUpTargetIndicator: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.red.withAlpha(76),
            shape: BoxShape.circle,
          ),
        ),
        dragRatio: 1,
        child: ListView.builder(
          itemCount: 20,
          itemBuilder: (context, index) {
            return ListTile(
              title: Text('Item $index'),
              subtitle: index == 0 
                ? Text('ここで下にプルダウンしてアクション選択') 
                : index == 19 
                  ? Text('ここで下にプルアップしてアクション選択') 
                  : null,
            );
          },
        ),
      ),
    );
  }
}
