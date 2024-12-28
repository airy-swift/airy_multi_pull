import 'dart:async';

import 'package:flutter/material.dart';

final class PullTarget extends StatelessWidget {
  const PullTarget({
    required GlobalKey key,
    required this.onPull,
    required this.child,
  }) : super(key: key);

  final FutureOr<void> Function() onPull;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
