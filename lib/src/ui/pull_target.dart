import 'dart:async';

import 'package:flutter/material.dart';

/// プルダウン操作のターゲットを表すウィジェット
///
/// このクラスはプルダウン操作でアクションを実行するためのターゲットを定義する。
/// [key]として[GlobalKey]が必要で、位置計算や識別に使用される。
/// [onPull]コールバックは、このターゲットが選択されたときに実行される。
/// [child]はターゲットの視覚的な表現（通常はアイコンなど）を提供する。
final class PullTarget extends StatelessWidget {
  /// PullTargetを作成する
  ///
  /// [key] ターゲットを識別するためのGlobalKey（必須）
  /// [onPull] ターゲットが選択されたときに実行されるコールバック
  /// [child] ターゲットの視覚的表現
  const PullTarget({
    required GlobalKey key,
    required this.onPull,
    required this.child,
  }) : super(key: key);

  /// ターゲットが選択されたときに実行されるコールバック
  final FutureOr<void> Function() onPull;

  /// ターゲットの視覚的表現
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
