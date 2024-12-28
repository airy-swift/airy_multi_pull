import 'dart:async';
import 'dart:math' as math;

import 'package:airy_multi_pull/src/extension/double_extension.dart';
import 'package:airy_multi_pull/src/extension/iterable_extension.dart';
import 'package:airy_multi_pull/src/ui/pull_target.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart';

const double _kDragContainerExtentPercentage = 0.25;
const double _kDragSizeFactorLimit = 1.5;
const Duration _kIndicatorSnapDuration = Duration(milliseconds: 150);
const Duration _kIndicatorScaleDuration = Duration(milliseconds: 200);

enum RefreshIndicatorStatus {
  drag,
  armed,
  snap,
  refresh,
  done,
  canceled,
}

enum RefreshIndicatorTriggerMode {
  anywhere,
  onEdge,
}

class AiryMultiPull extends StatefulWidget {
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

  final Widget child;
  final double displacement;
  final double edgeOffset;
  final ValueChanged<RefreshIndicatorStatus?>? onStatusChange;
  final Color? color;
  final Color? backgroundColor;
  final ScrollNotificationPredicate notificationPredicate;
  final String? semanticsLabel;
  final String? semanticsValue;
  final double strokeWidth;
  final RefreshIndicatorTriggerMode triggerMode;
  final double elevation;
  final Widget? targetIndicator;
  final double? dragRatio;
  final List<PullTarget> customIndicators;
  final Duration circleMoveDuration;
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
  late Color _effectiveValueColor = widget.color ?? Theme.of(context).colorScheme.primary;

  List<double> _customIndicatorXCenters = [];

  int _previousTargetIndex = 0;

  static final Animatable<double> _threeQuarterTween = Tween<double>(
    begin: 0.0,
    end: 0.75,
  );

  static final Animatable<double> _kDragSizeFactorLimitTween = Tween<double>(
    begin: 0.0,
    end: _kDragSizeFactorLimit,
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
    _targetIndicatorPositionXController = AnimationController(vsync: this, duration: Duration(seconds: 1));
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
    _effectiveValueColor = widget.color ?? Theme.of(context).colorScheme.primary;
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
            curve: const Interval(0.0, 1.0 / _kDragSizeFactorLimit),
          ),
        ),
      );
    }
  }

  bool _shouldStart(ScrollNotification notification) {
    return ((notification is ScrollStartNotification && notification.dragDetails != null) ||
        (notification is ScrollUpdateNotification && notification.dragDetails != null && widget.triggerMode == RefreshIndicatorTriggerMode.anywhere)) &&
        ((notification.metrics.axisDirection == AxisDirection.up && notification.metrics.extentAfter == 0.0) ||
            (notification.metrics.axisDirection == AxisDirection.down && notification.metrics.extentBefore == 0.0)) &&
        _status == null &&
        _start(notification.metrics.axisDirection);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.notificationPredicate(notification)) {
      return false;
    }
    if (_shouldStart(notification)) {
      setState(() {
        _status = RefreshIndicatorStatus.drag;
        widget.onStatusChange?.call(_status);
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _customIndicatorXCenters = widget.customIndicators.map((indicator) {
          final key = indicator.key as GlobalKey;
          final RenderBox renderBox = key.currentContext!.findRenderObject() as RenderBox;
          final Offset position = renderBox.localToGlobal(Offset.zero);
          return position.dx + renderBox.size.width / 2;
        }).toList();
        final centerIndex = _customIndicatorXCenters.getCenterIndex();
        _targetIndicatorPositionXController.value = _customIndicatorXCenters[centerIndex] / _screenWidth;
      });

      return false;
    }
    final bool? indicatorAtTopNow = switch (notification.metrics.axisDirection) {
      AxisDirection.down || AxisDirection.up => true,
      AxisDirection.left || AxisDirection.right => null,
    };
    if (indicatorAtTopNow != _isIndicatorAtTop) {
      if (_status == RefreshIndicatorStatus.drag || _status == RefreshIndicatorStatus.armed) {
        _dismiss(RefreshIndicatorStatus.canceled);
      }
    } else if (notification is ScrollUpdateNotification) {
      if (_status == RefreshIndicatorStatus.drag || _status == RefreshIndicatorStatus.armed) {
        if (notification.metrics.axisDirection == AxisDirection.down) {
          _dragOffset = _dragOffset! - notification.scrollDelta!;
        } else if (notification.metrics.axisDirection == AxisDirection.up) {
          _dragOffset = _dragOffset! + notification.scrollDelta!;
        }
        _checkDragOffset(notification.metrics.viewportDimension);
      }

      if (_status == RefreshIndicatorStatus.armed && notification.dragDetails != null) {
        _updateTargetPositionXByDragX(notification.dragDetails!);
      }

      if (_status == RefreshIndicatorStatus.armed && notification.dragDetails == null) {
        _show();
      }
    } else if (notification is OverscrollNotification) {
      if (_status == RefreshIndicatorStatus.drag || _status == RefreshIndicatorStatus.armed) {
        if (notification.metrics.axisDirection == AxisDirection.down) {
          _dragOffset = _dragOffset! - notification.overscroll;
        } else if (notification.metrics.axisDirection == AxisDirection.up) {
          _dragOffset = _dragOffset! + notification.overscroll;
        }

        if (_status == RefreshIndicatorStatus.armed && notification.dragDetails != null) {
          _updateTargetPositionXByDragX(notification.dragDetails!);
        }

        _checkDragOffset(notification.metrics.viewportDimension);
      }
    } else if (notification is ScrollEndNotification) {
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
    }
    return false;
  }

  void _updateTargetPositionXByDragX(DragUpdateDetails dragDetails) {
    _dragXOffset = dragDetails.globalPosition.dx;
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

  void _checkDragOffset(double containerExtent) {
    assert(_status == RefreshIndicatorStatus.drag || _status == RefreshIndicatorStatus.armed);
    double newValue = _dragOffset! / (containerExtent * _kDragContainerExtentPercentage);
    if (_status == RefreshIndicatorStatus.armed) {
      newValue = math.max(newValue, 1.0 / _kDragSizeFactorLimit);
    }
    _positionController.value = clampDouble(newValue, 0.0, 1.0);
    if (_status == RefreshIndicatorStatus.drag && _valueColor.value!.alpha == _effectiveValueColor.alpha) {
      _status = RefreshIndicatorStatus.armed;
      widget.onStatusChange?.call(_status);
    }
  }

  Future<void> _dismiss(RefreshIndicatorStatus newMode) async {
    await Future<void>.value();
    assert(newMode == RefreshIndicatorStatus.canceled || newMode == RefreshIndicatorStatus.done);
    setState(() {
      _status = newMode;
      widget.onStatusChange?.call(_status);
    });
    switch (_status!) {
      case RefreshIndicatorStatus.done:
        await _scaleController.animateTo(1.0, duration: _kIndicatorScaleDuration);
      case RefreshIndicatorStatus.canceled:
        await _positionController.animateTo(0.0, duration: _kIndicatorScaleDuration);
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

  bool _processByFuture = false;

  void _show() {
    assert(_status != RefreshIndicatorStatus.refresh);
    assert(_status != RefreshIndicatorStatus.snap);
    final Completer<void> completer = Completer<void>();
    _pendingRefreshFuture = completer.future;
    _status = RefreshIndicatorStatus.snap;
    widget.onStatusChange?.call(_status);
    _positionController.animateTo(1.0 / _kDragSizeFactorLimit, duration: _kIndicatorSnapDuration).then<void>((void value) {
      if (mounted && _status == RefreshIndicatorStatus.snap) {
        setState(() {
          _status = RefreshIndicatorStatus.refresh;
        });

        final targetPullCallback = widget.customIndicators[_previousTargetIndex].onPull;
        final FutureOr<void> refreshResult = targetPullCallback();

        if (refreshResult is Future<void>) {
          _processByFuture = true;
          refreshResult.whenComplete(() {
            if (mounted && _status == RefreshIndicatorStatus.refresh) {
              completer.complete();
              _dismiss(RefreshIndicatorStatus.done);
            }
          });
        } else {
          _processByFuture = false;
          if (mounted && _status == RefreshIndicatorStatus.refresh) {
            completer.complete();
            _dismiss(RefreshIndicatorStatus.done);
          }
        }
      }
    });
  }

  Future<void> show({bool atTop = true}) {
    if (_status != RefreshIndicatorStatus.refresh && _status != RefreshIndicatorStatus.snap) {
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
                            AnimatedBuilder(
                              animation: _targetIndicatorPositionXController,
                              builder: (context, child) => Transform.translate(
                                offset: Offset((_targetIndicatorPositionXController.value - 0.5) * _screenWidth, 0),
                                child: Visibility(
                                  visible: !showIndeterminateIndicator,
                                  child: widget.targetIndicator ??
                                      Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withValues(alpha: 0.3),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                ),
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 800),
                              reverseDuration: const Duration(milliseconds: 800),
                              child: _processByFuture && [RefreshIndicatorStatus.refresh, RefreshIndicatorStatus.done].contains(_status)
                                  ? RefreshProgressIndicator(
                                      semanticsLabel: widget.semanticsLabel ?? MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
                                      semanticsValue: widget.semanticsValue,
                                      value: showIndeterminateIndicator ? null : _value.value,
                                      valueColor: _valueColor,
                                      backgroundColor: widget.backgroundColor,
                                      strokeWidth: widget.strokeWidth,
                                      elevation: widget.elevation,
                                    )
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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