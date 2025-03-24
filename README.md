# Airy Multi Pull

複数のアクションを提供するFlutterプルダウンリフレッシュウィジェット。

[Multi Pull](https://pub.dev/packages/multi_pull)の後継プロジェクト。

![Demo](https://github.com/airyworks/airy_multi_pull/raw/main/doc/demo.gif)

## 特徴

- 複数のアクションターゲットを提供するプルダウンリフレッシュ機能
- 直感的なプルダウン操作と水平スワイプによるターゲット選択
- カスタマイズ可能なインジケーターとアニメーション
- 非同期アクションのサポート
- カスタムステータスコールバック

## インストール

```yaml
dependencies:
  airy_multi_pull: ^0.0.2
```

コマンドラインから:

```
flutter pub add airy_multi_pull
```

## 基本的な使い方

```dart
import 'package:airy_multi_pull/airy_multi_pull.dart';
import 'package:flutter/material.dart';

final firstKey = GlobalKey();
final secondKey = GlobalKey();

class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AiryMultiPull(
      customIndicators: [
        PullTarget(
          key: firstKey,
          onPull: () async {
            // 1つ目のアクション
            await Future.delayed(Duration(seconds: 1));
            print('Action 1');
          },
          child: Icon(Icons.refresh),
        ),
        PullTarget(
          key: secondKey,
          onPull: () {
            // 2つ目のアクション
            print('Action 2');
          },
          child: Icon(Icons.delete),
        ),
      ],
      // スクロール可能なウィジェット
      child: ListView.builder(
        itemCount: 50,
        itemBuilder: (context, index) => ListTile(
          title: Text('Item $index'),
        ),
      ),
    );
  }
}
```

## プロパティ

| プロパティ | 説明 |
|----------|------|
| `customIndicators` | `PullTarget`のリスト。各ターゲットには一意の`GlobalKey`が必要。 |
| `child` | スクロール可能な子ウィジェット。 |
| `displacement` | インジケーターの変位量。デフォルトは`40.0`。 |
| `targetIndicator` | 選択されたターゲットを示すインジケーター。 |
| `dragRatio` | ドラッグの比率。水平スワイプの感度を調整。 |
| `onStatusChange` | ステータス変更時のコールバック。 |
| `circleMoveDuration` | ターゲット間移動のアニメーション時間。 |
| `circleMoveCurve` | ターゲット間移動のアニメーションカーブ。 |

## 使用例

### 複数のアクションターゲット

```dart
AiryMultiPull(
  customIndicators: [
    PullTarget(
      key: GlobalKey(),
      onPull: () => refreshData(),
      child: Icon(Icons.refresh),
    ),
    PullTarget(
      key: GlobalKey(),
      onPull: () => deleteItem(),
      child: Icon(Icons.delete),
    ),
    PullTarget(
      key: GlobalKey(),
      onPull: () => addItem(),
      child: Icon(Icons.add),
    ),
  ],
  child: ListView(...),
)
```

### ステータス監視

```dart
AiryMultiPull(
  onStatusChange: (status) {
    print('Current status: $status');
  },
  customIndicators: [...],
  child: ListView(...),
)
```

### カスタムアニメーション

```dart
AiryMultiPull(
  circleMoveDuration: Duration(milliseconds: 500),
  circleMoveCurve: Curves.elasticOut,
  customIndicators: [...],
  child: ListView(...),
)
```

## 注意事項

- 各`PullTarget`は一意の`GlobalKey`を持つ必要があります
- `customIndicators`は空の配列でも動作しますが、少なくとも1つのターゲットを提供することをお勧めします
- 複雑な非同期操作を行う場合は、`onPull`コールバックで`Future`を返すことで、操作が完了するまでインジケーターが表示されます

## ライセンス

MIT License