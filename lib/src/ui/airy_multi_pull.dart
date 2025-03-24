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

/// リフレッシュインジケータのトリガーモードを表す列挙型
enum RefreshIndicatorTriggerMode {
  anywhere,
  onEdge,
}

/// 複数のプルターゲットを持つカスタムリフレッシュインジケータウィジェット
/// ユーザーは下方向にスクロールし、複数のアクションターゲットから選択できる
class AiryMultiPull extends StatefulWidget {
  /// AiryMultiPullウィジェットを作成する
  const AiryMultiPull({
    super.key,
    required this.child,
    this.displacement = 40.0,
    this.edgeOffset = 0.0,
    this.color,
    this.backgroundColor,
    this.notificationPredicate = defaultScrollNotificationPredicate,
    this.semanticsLabel,
    this.semanticsValue,
    this.strokeWidth = RefreshProgressIndicator.defaultStrokeWidth,
    this.triggerMode = RefreshIndicatorTriggerMode.anywhere,
    this.elevation = 2.0,
    this.onStatusChange,
    this.targetIndicator,
    this.dragRatio,
    required this.customIndicators,
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

  /// インジケータの色
  final Color? color;

  /// インジケータの背景色
  final Color? backgroundColor;

  /// スクロール通知のフィルター
  final ScrollNotificationPredicate notificationPredicate;

  /// アクセシビリティのためのセマンティクスラベル
  final String? semanticsLabel;

  /// アクセシビリティのためのセマンティクス値
  final String? semanticsValue;

  /// プログレスインジケータのストロークの幅
  final double strokeWidth;

  /// リフレッシュインジケータのトリガーモード
  final RefreshIndicatorTriggerMode triggerMode;

  /// インジケータの影の高さ
  final double elevation;

  /// ターゲットインジケータウィジェット
  final Widget? targetIndicator;

  /// ドラッグの比率
  final double? dragRatio;

  /// カスタムインジケータのリスト
  final List<PullTarget> customIndicators;

  /// サークル移動アニメーションの時間
  final Duration circleMoveDuration;

  /// サークル移動アニメーションのカーブ
  final Curve circleMoveCurve;

  @override
  AiryMultiPullState createState() => AiryMultiPullState();
}

class AiryMultiPullState extends State<AiryMultiPull>
    with TickerProviderStateMixin<AiryMultiPull> {
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
  late Color _effectiveValueColor =
      widget.color ?? Theme.of(context).colorScheme.primary;

  List<double> _customIndicatorXCenters = [];
  int _previousTargetIndex = 0;
  bool _processByFuture = false;

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
    _targetIndicatorPositionXController =
        AnimationController(vsync: this, duration: widget.circleMoveDuration);
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
    if (oldWidget.color != widget.color) {
      _setupColorTween();
    }
  }

  @override
  void dispose() {
    _positionController.dispose();
    _scaleController.dispose();
    _targetIndicatorPositionXController.dispose();
    super.dispose();
  }

  void _setupColorTween() {
    _effectiveValueColor =
        widget.color ?? Theme.of(context).colorScheme.primary;
    final Color color = _effectiveValueColor;
    if (color.alpha == 0x00) {
      _valueColor = AlwaysStoppedAnimation<Color>(color);
    } else {
      _valueColor = _positionController.drive(
        ColorTween(
          begin: color.withAlpha(0),
          end: color.withAlpha(color.alpha),
        ).chain(
          CurveTween(
            curve: const Interval(
                0.0, 1.0 / _AiryMultiPullConstants.dragSizeFactorLimit),
          ),
        ),
      );
    }
  }

  bool _shouldStart(ScrollNotification notification) {
    return ((notification is ScrollStartNotification &&
                notification.dragDetails != null) ||
            (notification is ScrollUpdateNotification &&
                notification.dragDetails != null &&
                widget.triggerMode == RefreshIndicatorTriggerMode.anywhere)) &&
        ((notification.metrics.axisDirection == AxisDirection.up &&
                notification.metrics.extentAfter == 0.0) ||
            (notification.metrics.axisDirection == AxisDirection.down &&
                notification.metrics.extentBefore == 0.0)) &&
        _status == null &&
        _start(notification.metrics.axisDirection);
  }

  double? _relativeStartPointX;

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
      if (_status == RefreshIndicatorStatus.drag ||
          _status == RefreshIndicatorStatus.armed) {
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

    // スクロール終了の処理
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateCustomIndicatorPositions();
    });

    return false;
  }

  /// カスタムインジケータの位置を計算する
  void _calculateCustomIndicatorPositions() {
    _customIndicatorXCenters = widget.customIndicators.map((indicator) {
      final key = indicator.key as GlobalKey;
      final RenderBox renderBox =
          key.currentContext!.findRenderObject() as RenderBox;
      final Offset position = renderBox.localToGlobal(Offset.zero);
      return position.dx + renderBox.size.width / 2;
    }).toList();
    final centerIndex = _customIndicatorXCenters.getCenterIndex();
    _targetIndicatorPositionXController.value =
        _customIndicatorXCenters[centerIndex] / _screenWidth;
  }

  /// スクロール方向を検出する
  bool? _detectScrollDirection(ScrollNotification notification) {
    return switch (notification.metrics.axisDirection) {
      AxisDirection.down || AxisDirection.up => true,
      AxisDirection.left || AxisDirection.right => null,
    };
  }

  /// スクロール更新時の処理
  bool _handleScrollUpdate(ScrollUpdateNotification notification) {
    _relativeStartPointX ??= notification.dragDetails?.globalPosition.dx;

    if (_status == RefreshIndicatorStatus.drag ||
        _status == RefreshIndicatorStatus.armed) {
      _updateDragOffset(
        notification.metrics.axisDirection,
        notification.scrollDelta!,
      );
      _checkDragOffset(notification.metrics.viewportDimension);
    }

    if (_status == RefreshIndicatorStatus.armed &&
        notification.dragDetails != null) {
      _updateTargetPositionXByDragX(notification.dragDetails!);
    }

    if (_status == RefreshIndicatorStatus.armed &&
        notification.dragDetails == null) {
      _show();
    }

    return false;
  }

  /// オーバースクロール時の処理
  bool _handleOverscroll(OverscrollNotification notification) {
    _relativeStartPointX ??= notification.dragDetails?.globalPosition.dx;

    if (_status == RefreshIndicatorStatus.drag ||
        _status == RefreshIndicatorStatus.armed) {
      _updateDragOffset(
        notification.metrics.axisDirection,
        notification.overscroll,
        isOverscroll: true,
      );

      if (_status == RefreshIndicatorStatus.armed &&
          notification.dragDetails != null) {
        _updateTargetPositionXByDragX(notification.dragDetails!);
      }

      _checkDragOffset(notification.metrics.viewportDimension);
    }

    return false;
  }

  /// ドラッグオフセットを更新する
  void _updateDragOffset(AxisDirection direction, double delta,
      {bool isOverscroll = false}) {
    if (direction == AxisDirection.down) {
      _dragOffset = _dragOffset! - delta;
    } else if (direction == AxisDirection.up) {
      _dragOffset = _dragOffset! + delta;
    }
  }

  /// スクロール終了時の処理
  bool _handleScrollEnd() {
    switch (_status) {
      case RefreshIndicatorStatus.armed:
        if (_positionController.value < 1.0) {
          _dismiss(RefreshIndicatorStatus.canceled);
        } else {
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

    // Calculate the relative movement from the start point
    final double relativeMovement =
        dragDetails.globalPosition.dx - _relativeStartPointX!;

    // Convert the relative movement to an absolute position
    _dragXOffset =
        (_screenWidth / 2) + relativeMovement * (widget.dragRatio ?? 1);

    final (targetIndex, closestValue) =
        _customIndicatorXCenters.closestValue(_dragXOffset!);
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

  bool _handleIndicatorNotification(
      OverscrollIndicatorNotification notification) {
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
      case AxisDirection.up:
        _isIndicatorAtTop = true;
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
    assert(_status == RefreshIndicatorStatus.drag ||
        _status == RefreshIndicatorStatus.armed);
    double newValue = _dragOffset! /
        (containerExtent *
            _AiryMultiPullConstants.dragContainerExtentPercentage);
    if (_status == RefreshIndicatorStatus.armed) {
      newValue =
          math.max(newValue, 1.0 / _AiryMultiPullConstants.dragSizeFactorLimit);
    }
    _positionController.value = clampDouble(newValue, 0.0, 1.0);
    if (_status == RefreshIndicatorStatus.drag &&
        _valueColor.value!.alpha == _effectiveValueColor.alpha) {
      _status = RefreshIndicatorStatus.armed;
      widget.onStatusChange?.call(_status);
    }
  }

  /// リフレッシュインジケータを非表示にする
  ///
  /// [newMode] 新しい状態（キャンセルまたは完了）
  Future<void> _dismiss(RefreshIndicatorStatus newMode) async {
    await Future<void>.value();
    assert(newMode == RefreshIndicatorStatus.canceled ||
        newMode == RefreshIndicatorStatus.done);
    setState(() {
      _status = newMode;
      widget.onStatusChange?.call(_status);
    });
    switch (_status!) {
      case RefreshIndicatorStatus.done:
        await _scaleController.animateTo(1.0,
            duration: _AiryMultiPullConstants.indicatorScaleDuration);
      case RefreshIndicatorStatus.canceled:
        await _positionController.animateTo(0.0,
            duration: _AiryMultiPullConstants.indicatorScaleDuration);
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
    final Completer<void> completer = Completer<void>();
    _pendingRefreshFuture = completer.future;
    _status = RefreshIndicatorStatus.snap;
    widget.onStatusChange?.call(_status);
    _positionController
        .animateTo(1.0 / _AiryMultiPullConstants.dragSizeFactorLimit,
            duration: _AiryMultiPullConstants.indicatorSnapDuration)
        .then<void>((void value) {
      if (mounted && _status == RefreshIndicatorStatus.snap) {
        setState(() {
          _status = RefreshIndicatorStatus.refresh;
        });

        // 選択されたターゲットのコールバックを実行
        final targetPullCallback =
            widget.customIndicators[_previousTargetIndex].onPull;
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
    if (_status != RefreshIndicatorStatus.refresh &&
        _status != RefreshIndicatorStatus.snap) {
      if (_status == null) {
        _start(atTop ? AxisDirection.down : AxisDirection.up);
      }
      _show();
    }
    return _pendingRefreshFuture;
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

    final bool showIndeterminateIndicator =
        _status == RefreshIndicatorStatus.refresh ||
            _status == RefreshIndicatorStatus.done;

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
                padding: _isIndicatorAtTop!
                    ? EdgeInsets.only(top: widget.displacement)
                    : EdgeInsets.only(bottom: widget.displacement),
                child: Align(
                  alignment: _isIndicatorAtTop!
                      ? Alignment.topCenter
                      : Alignment.bottomCenter,
                  child: ScaleTransition(
                    scale: _scaleFactor,
                    child: AnimatedBuilder(
                      animation: _positionController,
                      builder: (BuildContext context, Widget? child) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            AnimatedBuilder(
                              animation: _targetIndicatorPositionXController,
                              builder: (context, child) => Transform.translate(
                                offset: Offset(
                                    (_targetIndicatorPositionXController.value -
                                            0.5) *
                                        _screenWidth,
                                    0),
                                child: Visibility(
                                  visible: !showIndeterminateIndicator,
                                  child: widget.targetIndicator ??
                                      Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          color: Colors.grey
                                              .withValues(alpha: 0.3),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                ),
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 800),
                              reverseDuration:
                                  const Duration(milliseconds: 800),
                              child: _processByFuture &&
                                      [
                                        RefreshIndicatorStatus.refresh,
                                        RefreshIndicatorStatus.done
                                      ].contains(_status)
                                  ? RefreshProgressIndicator(
                                      semanticsLabel: widget.semanticsLabel ??
                                          MaterialLocalizations.of(context)
                                              .refreshIndicatorSemanticLabel,
                                      semanticsValue: widget.semanticsValue,
                                      value: showIndeterminateIndicator
                                          ? null
                                          : _value.value,
                                      valueColor: _valueColor,
                                      backgroundColor: widget.backgroundColor,
                                      strokeWidth: widget.strokeWidth,
                                      elevation: widget.elevation,
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: widget.customIndicators,
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
