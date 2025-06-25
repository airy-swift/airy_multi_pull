import 'dart:async';
import 'dart:math' as math;

import 'package:airy_multi_pull/src/extension/double_extension.dart';
import 'package:airy_multi_pull/src/extension/iterable_extension.dart';
import 'package:airy_multi_pull/src/ui/pull_target.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart';

/// 定数の集中管理
class _AiryMultiPullConstants {
  /// ドラッグコンテナの範囲の割合
  static const double dragContainerExtentPercentage = 0.10;

  /// ドラッグサイズファクターの制限
  static const double dragSizeFactorLimit = 1.5;

  /// インジケータスナップのアニメーション時間
  static const Duration indicatorSnapDuration = Duration(milliseconds: 150);

  /// インジケータスケールのアニメーション時間
  static const Duration indicatorScaleDuration = Duration(milliseconds: 200);

  /// ドラッグキャンセルの閾値（この値以下になるとキャンセルされる）
  static const double dragCancelThreshold = 0.3;
}

/// リフレッシュインジケータの状態を表す列挙型
enum RefreshIndicatorStatus {
  drag,
  armed,
  snap,
  refresh,
  done,
  canceled,
}

/// 複数のプルターゲットを持つカスタムリフレッシュインジケータウィジェット
/// ユーザーは上部からのプルダウンまたは下部からのプルアップで、複数のアクションターゲットから選択できる
class AiryMultiPull extends StatefulWidget {
  /// AiryMultiPullウィジェットを作成する
  const AiryMultiPull({
    super.key,
    required this.child,
    this.displacement = 20.0,
    this.edgeOffset = 0.0,
    this.notificationPredicate = defaultScrollNotificationPredicate,
    this.elevation = 2.0,
    this.onStatusChange,
    this.onArmed,
    this.targetIndicator,
    this.dragRatio,
    // プルダウン用のプロパティ
    this.pullDownCustomIndicators = const [],
    this.pullDownTargetIndicator,
    // プルアップ用のプロパティ
    this.pullUpCustomIndicators = const [],
    this.pullUpTargetIndicator,
    // 後方互換性のため残す（非推奨）
    this.customIndicators = const [],
    this.circleMoveDuration = const Duration(milliseconds: 300),
    this.circleMoveCurve = Curves.easeInOut,
  }) : assert(elevation >= 0.0);

  /// スクロール可能な子ウィジェット
  final Widget child;

  /// インジケータの変位量
  final double displacement;

  /// エッジからのオフセット
  final double edgeOffset;

  /// ステータス変更時のコールバック
  final ValueChanged<RefreshIndicatorStatus?>? onStatusChange;

  /// Armed状態になったときのコールバック
  /// ハプティックフィードバックなどのカスタム処理を追加するのに便利
  final VoidCallback? onArmed;

  /// スクロール通知のフィルター
  final ScrollNotificationPredicate notificationPredicate;

  /// インジケータの影の高さ
  final double elevation;

  /// ターゲットインジケータウィジェット（後方互換性のため残す）
  final Widget? targetIndicator;

  /// ドラッグの比率
  final double? dragRatio;

  /// プルダウン用のカスタムインジケータのリスト
  final List<PullTarget> pullDownCustomIndicators;

  /// プルダウン用のターゲットインジケータウィジェット
  final Widget? pullDownTargetIndicator;

  /// プルアップ用のカスタムインジケータのリスト
  final List<PullTarget> pullUpCustomIndicators;

  /// プルアップ用のターゲットインジケータウィジェット
  final Widget? pullUpTargetIndicator;

  /// カスタムインジケータのリスト（後方互換性のため残す、非推奨）
  @Deprecated('Use pullDownCustomIndicators and pullUpCustomIndicators instead')
  final List<PullTarget> customIndicators;

  /// サークル移動アニメーションの時間
  final Duration circleMoveDuration;

  /// サークル移動アニメーションのカーブ
  final Curve circleMoveCurve;

  @override
  AiryMultiPullState createState() => AiryMultiPullState();
}

class AiryMultiPullState extends State<AiryMultiPull> with TickerProviderStateMixin<AiryMultiPull> {
  late AnimationController _positionController;
  late AnimationController _scaleController;
  late AnimationController _targetIndicatorPositionXController;
  late Animation<double> _positionFactor;
  late Animation<double> _scaleFactor;
  late Animation<double> _value;
  late Animation<Color?> _valueColor;

  RefreshIndicatorStatus? _status;
  late Future<void> _pendingRefreshFuture;
  bool? _isIndicatorAtTop;
  double? _dragOffset;
  double? _dragXOffset;
  late double _screenWidth;
  late Color _effectiveValueColor = Theme.of(context).colorScheme.primary;

  List<double> _customIndicatorXCenters = [];
  int _previousTargetIndex = 0;
  bool _processByFuture = false;

  // 水平方向のドラッグ開始位置
  double? _relativeStartPointX;

  static final Animatable<double> _threeQuarterTween = Tween<double>(
    begin: 0.0,
    end: 0.75,
  );

  static final Animatable<double> _kDragSizeFactorLimitTween = Tween<double>(
    begin: 0.0,
    end: _AiryMultiPullConstants.dragSizeFactorLimit,
  );

  static final Animatable<double> _oneToZeroTween = Tween<double>(
    begin: 1.0,
    end: 0.0,
  );

  @override
  void initState() {
    super.initState();
    _positionController = AnimationController(vsync: this);
    _scaleController = AnimationController(vsync: this);
    _targetIndicatorPositionXController = AnimationController(vsync: this, duration: widget.circleMoveDuration);
    _positionFactor = _positionController.drive(_kDragSizeFactorLimitTween);
    _value = _positionController.drive(_threeQuarterTween);
    _scaleFactor = _scaleController.drive(_oneToZeroTween);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _screenWidth = MediaQuery.of(context).size.width;
    });
  }

  @override
  void didChangeDependencies() {
    _setupColorTween();
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(covariant AiryMultiPull oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _positionController.dispose();
    _scaleController.dispose();
    _targetIndicatorPositionXController.dispose();
    super.dispose();
  }

  void _setupColorTween() {
    _effectiveValueColor = Theme.of(context).colorScheme.primary;
    final Color color = _effectiveValueColor;
    // a値が0の場合、透明色になるため特別扱い
    if (color.a == 0x00) {
      _valueColor = AlwaysStoppedAnimation<Color>(color);
    } else {
      _valueColor = _positionController.drive(
        ColorTween(
          begin: color.withAlpha(0),
          end: color.withAlpha(color.a.toInt()),
        ).chain(
          CurveTween(
            curve: const Interval(0.0, 1.0 / _AiryMultiPullConstants.dragSizeFactorLimit),
          ),
        ),
      );
    }
  }

  bool _shouldStart(ScrollNotification notification) {
    if (!((notification is ScrollStartNotification && notification.dragDetails != null) || (notification is ScrollUpdateNotification && notification.dragDetails != null))) {
      return false;
    }

    if (_status != null) {
      return false;
    }

    // プルダウンとプルアップの検出を分離
    if (_shouldStartPullDown(notification)) {
      _start(AxisDirection.down);
      return true; // _handleScrollStartを呼び出すためにtrueを返す
    } else if (_shouldStartPullUp(notification)) {
      _start(AxisDirection.up);
      return true; // _handleScrollStartを呼び出すためにtrueを返す
    }

    return false;
  }

  /// プルダウン操作の開始条件を判定する
  /// 上端にいて、さらに下方向にドラッグした場合のみtrueを返す
  bool _shouldStartPullDown(ScrollNotification notification) {
    // リストの一番上にいることを確認
    final bool atTop = notification.metrics.extentBefore == 0.0;

    if (!atTop) return false;

    // プルダウン用のインジケーターが設定されていることを確認
    // 後方互換性のため、customIndicatorsもチェック
    if (widget.pullDownCustomIndicators.isEmpty &&
        // ignore: deprecated_member_use_from_same_package
        widget.customIndicators.isEmpty) {
      return false;
    }

    // ScrollStartNotificationの場合は位置条件のみで判定（より確実）
    if (notification is ScrollStartNotification) {
      return true;
    }

    // ScrollUpdateNotificationの場合、より緩い条件で判定
    if (notification is ScrollUpdateNotification) {
      // scrollDeltaが負の値またはnullの場合（プルダウンの可能性）
      return notification.scrollDelta == null || notification.scrollDelta! <= 0;
    }

    return false;
  }

  /// プルアップ操作の開始条件を判定する
  /// 下端にいて、さらに上方向にドラッグした場合のみtrueを返す
  bool _shouldStartPullUp(ScrollNotification notification) {
    // リストの一番下にいることを確認
    final bool atBottom = notification.metrics.extentAfter == 0.0;

    if (!atBottom) return false;

    // プルアップ用のインジケーターが設定されていることを確認
    if (widget.pullUpCustomIndicators.isEmpty) {
      return false;
    }

    // ScrollStartNotificationの場合は位置条件のみで判定（より確実）
    if (notification is ScrollStartNotification) {
      return true;
    }

    // ScrollUpdateNotificationの場合、より緩い条件で判定
    if (notification is ScrollUpdateNotification) {
      // scrollDeltaが正の値またはnullの場合（プルアップの可能性）
      return notification.scrollDelta == null || notification.scrollDelta! >= 0;
    }

    return false;
  }

  /// スクロール通知を処理し、プルダウン操作を検出する
  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.notificationPredicate(notification)) {
      return false;
    }

    // プル操作開始の検出
    if (_shouldStart(notification)) {
      return _handleScrollStart();
    }

    // スクロール方向の検出
    final bool? indicatorAtTopNow = _detectScrollDirection(notification);
    if (indicatorAtTopNow != _isIndicatorAtTop) {
      if (_status == RefreshIndicatorStatus.drag || _status == RefreshIndicatorStatus.armed) {
        _dismiss(RefreshIndicatorStatus.canceled);
      }
      return false;
    }

    // スクロール更新の処理
    if (notification is ScrollUpdateNotification) {
      return _handleScrollUpdate(notification);
    }

    // オーバースクロールの処理
    if (notification is OverscrollNotification) {
      return _handleOverscroll(notification);
    }

    // スクロール終了の処理（指を離した時）
    if (notification is ScrollEndNotification) {
      return _handleScrollEnd();
    }

    return false;
  }

  /// スクロール開始時の処理
  bool _handleScrollStart() {
    setState(() {
      _status = RefreshIndicatorStatus.drag;
      widget.onStatusChange?.call(_status);
    });

    _dragOffset = 0.0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateCustomIndicatorPositions();
    });

    return false;
  }

  /// カスタムインジケータの位置を計算する
  void _calculateCustomIndicatorPositions() {
    try {
      final currentIndicators = _currentCustomIndicators;
      _customIndicatorXCenters = currentIndicators.map((indicator) {
        try {
          final key = indicator.key as GlobalKey;
          // コンテキストがnullかチェック
          if (key.currentContext == null) {
            return _screenWidth / 2; // デフォルト値として画面中央を使用
          }

          final RenderBox renderBox = key.currentContext!.findRenderObject() as RenderBox;
          final Offset position = renderBox.localToGlobal(Offset.zero);
          return position.dx + renderBox.size.width / 2;
        } catch (e) {
          // エラーが発生した場合はデフォルト値を使用
          return _screenWidth / 2;
        }
      }).toList();

      // リストが空でないことを確認
      if (_customIndicatorXCenters.isEmpty) {
        // デフォルトとして画面中央の位置を追加
        _customIndicatorXCenters = [_screenWidth / 2];
      }

      final centerIndex = _customIndicatorXCenters.getCenterIndex();
      _targetIndicatorPositionXController.value = _customIndicatorXCenters[centerIndex] / _screenWidth;
    } catch (e) {
      // 予期せぬエラーが発生した場合も最低限の値を設定
      _customIndicatorXCenters = [_screenWidth / 2];
      _targetIndicatorPositionXController.value = 0.5; // 画面中央
    }
  }

  /// スクロール方向を検出する
  bool? _detectScrollDirection(ScrollNotification notification) {
    return switch (notification.metrics.axisDirection) {
      // 現在設定されているインジケータ位置を維持
      AxisDirection.down || AxisDirection.up => _isIndicatorAtTop,
      AxisDirection.left || AxisDirection.right => null,
    };
  }

  /// スクロール更新時の処理
  bool _handleScrollUpdate(ScrollUpdateNotification notification) {
    // 既にインジケータが表示されている場合のみ処理を継続
    if (_status != RefreshIndicatorStatus.drag && _status != RefreshIndicatorStatus.armed) {
      return false;
    }

    // プルダウンかプルアップかによって処理を分離
    if (_isIndicatorAtTop!) {
      return _handlePullDownScrollUpdate(notification);
    } else {
      return _handlePullUpScrollUpdate(notification);
    }
  }

  double? downDragOffset;

  /// プルダウンのスクロール更新処理
  bool _handlePullDownScrollUpdate(ScrollUpdateNotification notification) {
    // インジケーター表示中は位置チェックを緩和
    // 完全に無効化して処理を継続
    final delta = notification.scrollDelta ?? 0;
    if (delta > 0) {
      if (notification.dragDetails?.globalPosition.dy == null) {
        return false;
      }
      downDragOffset ??= notification.dragDetails!.globalPosition.dy;
      if (downDragOffset! > (notification.dragDetails!.globalPosition.dy + (widget.displacement * 2))) {
        _dismiss(RefreshIndicatorStatus.canceled);
        downDragOffset = null;
      }
      return false;
    }

    _relativeStartPointX ??= notification.dragDetails?.globalPosition.dx;

    final double oldDragOffset = _dragOffset!;

    _updateDragOffset(notification.metrics.axisDirection, notification.scrollDelta!);

    // キャンセル判定の処理
    _handleDragCancelCheck(oldDragOffset, notification.metrics.viewportDimension);

    _checkDragOffset(notification.metrics.viewportDimension);

    if (_status == RefreshIndicatorStatus.armed && notification.dragDetails != null) {
      _updateTargetPositionXByDragX(notification.dragDetails!);
    }

    return false;
  }

  double? upDragOffset;

  /// プルアップのスクロール更新処理
  bool _handlePullUpScrollUpdate(ScrollUpdateNotification notification) {
    // インジケーター表示中は位置チェックを緩和
    // 完全に無効化して処理を継続
    final delta = notification.scrollDelta ?? 0;
    if (delta < 0) {
      if (notification.dragDetails?.globalPosition.dy == null) {
        return false;
      }
      upDragOffset ??= notification.dragDetails!.globalPosition.dy;
      if (upDragOffset! < (notification.dragDetails!.globalPosition.dy - (widget.displacement * 2))) {
        _dismiss(RefreshIndicatorStatus.canceled);
        upDragOffset = null;
      }
      return false;
    }

    _relativeStartPointX ??= notification.dragDetails?.globalPosition.dx;

    final double oldDragOffset = _dragOffset!;

    _updateDragOffset(notification.metrics.axisDirection, notification.scrollDelta!);

    // キャンセル判定の処理
    _handleDragCancelCheck(oldDragOffset, notification.metrics.viewportDimension);

    _checkDragOffset(notification.metrics.viewportDimension);

    if (_status == RefreshIndicatorStatus.armed && notification.dragDetails != null) {
      _updateTargetPositionXByDragX(notification.dragDetails!);
    }

    return false;
  }

  /// オーバースクロール時の処理
  bool _handleOverscroll(OverscrollNotification notification) {
    // 既にインジケータが表示されている場合のみ処理を継続
    if (_status != RefreshIndicatorStatus.drag && _status != RefreshIndicatorStatus.armed) {
      return false;
    }

    // プルダウンかプルアップかによって処理を分離
    if (_isIndicatorAtTop!) {
      return _handlePullDownOverscroll(notification);
    } else {
      return _handlePullUpOverscroll(notification);
    }
  }

  /// プルダウンのオーバースクロール処理
  bool _handlePullDownOverscroll(OverscrollNotification notification) {
    // インジケーター表示中は位置チェックを緩和
    // 完全に無効化して処理を継続

    // 下方向のオーバースクロール（正の値）の場合のみ処理
    // 条件を緩和：0以下ではなく負の値のみ除外
    if (notification.overscroll > 0) {
      return false;
    }

    _relativeStartPointX ??= notification.dragDetails?.globalPosition.dx;

    final double oldDragOffset = _dragOffset!;

    _updateDragOffset(notification.metrics.axisDirection, notification.overscroll, isOverscroll: true);

    // キャンセル判定の処理
    _handleDragCancelCheck(oldDragOffset, notification.metrics.viewportDimension);

    if (_status == RefreshIndicatorStatus.armed && notification.dragDetails != null) {
      _updateTargetPositionXByDragX(notification.dragDetails!);
    }

    _checkDragOffset(notification.metrics.viewportDimension);
    return false;
  }

  /// プルアップのオーバースクロール処理
  bool _handlePullUpOverscroll(OverscrollNotification notification) {
    // インジケーター表示中は位置チェックを緩和
    // 完全に無効化して処理を継続

    // 上方向のオーバースクロール（負の値）の場合のみ処理
    // 条件を緩和：0以上ではなく正の値のみ除外
    if (notification.overscroll < 0) {
      return false;
    }

    _relativeStartPointX ??= notification.dragDetails?.globalPosition.dx;

    final double oldDragOffset = _dragOffset!;

    // プルアップの場合は負の値を正の値に変換して処理
    _updateDragOffset(notification.metrics.axisDirection, -notification.overscroll, isOverscroll: true);

    // キャンセル判定の処理
    _handleDragCancelCheck(oldDragOffset, notification.metrics.viewportDimension);

    if (_status == RefreshIndicatorStatus.armed && notification.dragDetails != null) {
      _updateTargetPositionXByDragX(notification.dragDetails!);
    }

    _checkDragOffset(notification.metrics.viewportDimension);
    return false;
  }

  /// ドラッグキャンセル判定の共通処理
  void _handleDragCancelCheck(double oldDragOffset, double viewportDimension) {
    // キャンセル判定: Y軸方向でスクロール開始位置付近に戻ったか
    if (_status == RefreshIndicatorStatus.armed) {
      // ドラッグが元の位置に近づいている（上方向へのスクロール）
      if (_dragOffset! < oldDragOffset) {
        // 閾値よりも小さくなったらキャンセル
        final double thresholdDistance = _AiryMultiPullConstants.dragCancelThreshold * (viewportDimension * _AiryMultiPullConstants.dragContainerExtentPercentage);

        if (_dragOffset! <= thresholdDistance) {
          _dismiss(RefreshIndicatorStatus.canceled);
        }
      }
    }
  }

  /// ドラッグオフセットを更新する
  void _updateDragOffset(AxisDirection direction, double delta, {bool isOverscroll = false}) {
    // インジケータの位置に基づいて適切な計算を行う
    if (_isIndicatorAtTop!) {
      // プルダウン（上部表示）の場合：上部で下方向にドラッグ
      if (direction == AxisDirection.down) {
        _dragOffset = _dragOffset! + delta.abs();
      } else {
        // 戻る方向（上方向）
        _dragOffset = _dragOffset! - delta.abs();
      }
    } else {
      // プルアップ（下部表示）の場合：下部で下方向にドラッグ
      if (direction == AxisDirection.down) {
        _dragOffset = _dragOffset! + delta.abs();
      } else {
        // 戻る方向（上方向）
        _dragOffset = _dragOffset! - delta.abs();
      }
    }

    // ドラッグオフセットが負の値にならないようにする
    if (_dragOffset! < 0.0) {
      _dragOffset = 0.0;
    }
  }

  /// スクロール終了時の処理（指を離した時）
  bool _handleScrollEnd() {
    switch (_status) {
      case RefreshIndicatorStatus.armed:
        // 元の位置に十分に近い場合はキャンセル、そうでなければアクション実行
        final double thresholdDistance = _AiryMultiPullConstants.dragCancelThreshold * (MediaQuery.of(context).size.height * _AiryMultiPullConstants.dragContainerExtentPercentage);

        if (_dragOffset == null || _dragOffset! < thresholdDistance) {
          _dismiss(RefreshIndicatorStatus.canceled);
        } else {
          // 指を離した時にアクションを実行
          _show();
        }
      case RefreshIndicatorStatus.drag:
        _dismiss(RefreshIndicatorStatus.canceled);
      case RefreshIndicatorStatus.canceled:
      case RefreshIndicatorStatus.done:
      case RefreshIndicatorStatus.refresh:
      case RefreshIndicatorStatus.snap:
      case null:
        break;
    }
    return false;
  }

  void _updateTargetPositionXByDragX(DragUpdateDetails dragDetails) {
    if (_relativeStartPointX == null) return;

    // カスタムインジケータのリストが空の場合は処理をスキップ
    if (_customIndicatorXCenters.isEmpty) {
      return;
    }

    // Calculate the relative movement from the start point
    final double relativeMovement = dragDetails.globalPosition.dx - _relativeStartPointX!;

    // Convert the relative movement to an absolute position
    _dragXOffset = (_screenWidth / 2) + relativeMovement * (widget.dragRatio ?? 1);

    final (targetIndex, closestValue) = _customIndicatorXCenters.closestValue(_dragXOffset!);
    final ratio = closestValue / _screenWidth;
    if (_previousTargetIndex == targetIndex) {
      return;
    }
    _previousTargetIndex = targetIndex;
    _targetIndicatorPositionXController.animateTo(
      ratio,
      duration: widget.circleMoveDuration,
      curve: widget.circleMoveCurve,
    );
  }

  bool _handleIndicatorNotification(OverscrollIndicatorNotification notification) {
    if (notification.depth != 0 || !notification.leading) {
      return false;
    }
    if (_status == RefreshIndicatorStatus.drag) {
      notification.disallowIndicator();
      return true;
    }
    return false;
  }

  /// 指定された方向のプル操作を開始する
  bool _start(AxisDirection direction) {
    assert(_status == null);
    assert(_isIndicatorAtTop == null);
    assert(_dragOffset == null);
    switch (direction) {
      case AxisDirection.down:
        // プルダウン操作（上部に表示）
        _isIndicatorAtTop = true;
      case AxisDirection.up:
        // プルアップ操作（下部に表示）
        _isIndicatorAtTop = false;
      case AxisDirection.left:
      case AxisDirection.right:
        _isIndicatorAtTop = null;
        return false;
    }
    _dragOffset = 0.0;
    _scaleController.value = 0.0;
    _positionController.value = 0.0;
    return true;
  }

  /// ドラッグオフセットをチェックし、状態を更新する
  void _checkDragOffset(double containerExtent) {
    double newValue = _dragOffset! / (containerExtent * _AiryMultiPullConstants.dragContainerExtentPercentage);

    if (_status == RefreshIndicatorStatus.armed) {
      newValue = math.max(newValue, 1.0 / _AiryMultiPullConstants.dragSizeFactorLimit);
    }
    _positionController.value = clampDouble(newValue, 0.0, 1.0);

    // ドラッグが十分な距離に達したらarmed状態に変更
    // テスト環境でも確実に動作するように条件を微調整
    if (_status == RefreshIndicatorStatus.drag) {
      final double threshold = 1.0 / _AiryMultiPullConstants.dragSizeFactorLimit;
      if (_positionController.value >= threshold) {
        _status = RefreshIndicatorStatus.armed;
        widget.onStatusChange?.call(_status);
        // Armed状態になったときのコールバックを呼び出す
        widget.onArmed?.call();
      }
    }
  }

  /// リフレッシュインジケータを非表示にする
  ///
  /// [newMode] 新しい状態（キャンセルまたは完了）
  Future<void> _dismiss(RefreshIndicatorStatus newMode) async {
    await Future<void>.value();
    assert(newMode == RefreshIndicatorStatus.canceled || newMode == RefreshIndicatorStatus.done);
    setState(() {
      _status = newMode;
      widget.onStatusChange?.call(_status);
    });
    switch (_status!) {
      case RefreshIndicatorStatus.done:
        await _scaleController.animateTo(1.0, duration: _AiryMultiPullConstants.indicatorScaleDuration);
      case RefreshIndicatorStatus.canceled:
        await _positionController.animateTo(0.0, duration: _AiryMultiPullConstants.indicatorScaleDuration);
      case RefreshIndicatorStatus.armed:
      case RefreshIndicatorStatus.drag:
      case RefreshIndicatorStatus.refresh:
      case RefreshIndicatorStatus.snap:
        assert(false);
    }
    if (mounted && _status == newMode) {
      _dragOffset = null;
      _isIndicatorAtTop = null;
      setState(() {
        _status = null;
      });
    }
  }

  /// リフレッシュインジケータを表示し、選択されたアクションを実行する
  void _show() {
    assert(_status != RefreshIndicatorStatus.refresh);
    assert(_status != RefreshIndicatorStatus.snap);

    // 現在のカスタムインジケータが空の場合は早期リターン
    final currentIndicators = _currentCustomIndicators;
    if (currentIndicators.isEmpty) {
      final Completer<void> completer = Completer<void>();
      _pendingRefreshFuture = completer.future;
      completer.complete();
      _dismiss(RefreshIndicatorStatus.done);
      _relativeStartPointX = null;
      return;
    }

    final Completer<void> completer = Completer<void>();
    _pendingRefreshFuture = completer.future;
    _status = RefreshIndicatorStatus.snap;
    widget.onStatusChange?.call(_status);
    _positionController.animateTo(1.0 / _AiryMultiPullConstants.dragSizeFactorLimit, duration: _AiryMultiPullConstants.indicatorSnapDuration).then<void>((void value) {
      if (mounted && _status == RefreshIndicatorStatus.snap) {
        setState(() {
          _status = RefreshIndicatorStatus.refresh;
        });

        // 選択されたターゲットのコールバックを実行
        // 安全のため範囲チェックを追加
        final targetIndex = _previousTargetIndex.clamp(0, currentIndicators.length - 1);
        final targetPullCallback = currentIndicators[targetIndex].onPull;
        final FutureOr<void> refreshResult = targetPullCallback();

        // コールバック完了時の処理
        complete() {
          if (mounted && _status == RefreshIndicatorStatus.refresh) {
            completer.complete();
            _dismiss(RefreshIndicatorStatus.done);
            _relativeStartPointX = null;
          }
        }

        if (refreshResult is Future<void>) {
          _processByFuture = true;
          refreshResult.whenComplete(complete);
        } else {
          _processByFuture = false;
          complete();
        }
      }
    });
  }

  /// プログラムからリフレッシュインジケータを表示する
  ///
  /// [atTop] インジケータを上部に表示するかどうか
  Future<void> show({bool atTop = true}) {
    if (_status != RefreshIndicatorStatus.refresh && _status != RefreshIndicatorStatus.snap) {
      if (_status == null) {
        _start(atTop ? AxisDirection.down : AxisDirection.up);
      }
      _show();
    }
    return _pendingRefreshFuture;
  }

  /// 現在のプル方向に応じてカスタムインジケータのリストを取得
  List<PullTarget> get _currentCustomIndicators {
    if (_isIndicatorAtTop == null) {
      // ignore: deprecated_member_use_from_same_package
      if (widget.customIndicators.isNotEmpty) {
        // ignore: deprecated_member_use_from_same_package
        return widget.customIndicators;
      }
      return [];
    }

    if (_isIndicatorAtTop!) {
      return widget.pullDownCustomIndicators.isNotEmpty
          ? widget.pullDownCustomIndicators
          // ignore: deprecated_member_use_from_same_package
          : widget.customIndicators;
    } else {
      return widget.pullUpCustomIndicators.isNotEmpty
          ? widget.pullUpCustomIndicators
          // ignore: deprecated_member_use_from_same_package
          : widget.customIndicators;
    }
  }

  /// 現在のプル方向に応じてターゲットインジケータを取得
  Widget? get _currentTargetIndicator {
    if (_isIndicatorAtTop == null) {
      return widget.targetIndicator;
    }

    if (_isIndicatorAtTop!) {
      return widget.pullDownTargetIndicator ?? widget.targetIndicator;
    } else {
      return widget.pullUpTargetIndicator ?? widget.targetIndicator;
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasMaterialLocalizations(context));
    final Widget child = NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: NotificationListener<OverscrollIndicatorNotification>(
        onNotification: _handleIndicatorNotification,
        child: widget.child,
      ),
    );
    assert(() {
      if (_status == null) {
        assert(_dragOffset == null);
        assert(_isIndicatorAtTop == null);
      } else {
        assert(_dragOffset != null);
        assert(_isIndicatorAtTop != null);
      }
      return true;
    }());

    final bool showIndeterminateIndicator = _status == RefreshIndicatorStatus.refresh || _status == RefreshIndicatorStatus.done;

    return Stack(
      children: <Widget>[
        child,
        if (_status != null)
          Positioned(
            top: _isIndicatorAtTop! ? widget.edgeOffset : null,
            bottom: !_isIndicatorAtTop! ? widget.edgeOffset : null,
            left: 0.0,
            right: 0.0,
            child: SizeTransition(
              axisAlignment: _isIndicatorAtTop! ? 1.0 : -1.0,
              sizeFactor: _positionFactor,
              child: Padding(
                padding: _isIndicatorAtTop! ? EdgeInsets.only(top: widget.displacement) : EdgeInsets.only(bottom: widget.displacement),
                child: Align(
                  alignment: _isIndicatorAtTop! ? Alignment.topCenter : Alignment.bottomCenter,
                  child: ScaleTransition(
                    scale: _scaleFactor,
                    child: AnimatedBuilder(
                      animation: _positionController,
                      builder: (BuildContext context, Widget? child) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            // ターゲットインジケーターの表示
                            AnimatedBuilder(
                              animation: _targetIndicatorPositionXController,
                              builder: (context, child) => Transform.translate(
                                offset: Offset((_targetIndicatorPositionXController.value - 0.5) * _screenWidth, 0),
                                child: Visibility(
                                  visible: !showIndeterminateIndicator,
                                  child: _currentTargetIndicator ??
                                      Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withAlpha(76),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                ),
                              ),
                            ),
                            // カスタムインジケーターまたはプログレスインジケーターの表示
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 800),
                              reverseDuration: const Duration(milliseconds: 800),
                              child: _processByFuture && [RefreshIndicatorStatus.refresh, RefreshIndicatorStatus.done].contains(_status)
                                  ? RefreshProgressIndicator(
                                      value: showIndeterminateIndicator ? null : _value.value,
                                      valueColor: _valueColor,
                                      strokeWidth: 2.0,
                                      elevation: widget.elevation,
                                    )
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: _currentCustomIndicators,
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
