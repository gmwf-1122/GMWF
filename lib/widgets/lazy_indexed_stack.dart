// lib/widgets/lazy_indexed_stack.dart
//
// Drop-in replacement for IndexedStack that only builds a child the first time it is shown.
// A plain IndexedStack inflates EVERY tab up front and keeps all of them reacting to every data
// change (Hive listeners, realtime streams, timers), which made navigating the dispensary and
// server screens slow. Visited tabs stay alive (their state survives), but hidden ones have
// their tickers/animations paused.

import 'package:flutter/material.dart';

import '../utils/ui_stall_monitor.dart';

class LazyIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final AlignmentGeometry alignment;
  final StackFit sizing;

  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.alignment = AlignmentDirectional.topStart,
    this.sizing = StackFit.loose,
  });

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  final Set<int> _visited = <int>{};
  int? _lastShown;

  @override
  Widget build(BuildContext context) {
    final count = widget.children.length;
    final current = count == 0 ? 0 : widget.index.clamp(0, count - 1);
    if (_visited.add(current)) {
      UiStallMonitor.mark('first open of tab #$current');
    } else if (_lastShown != current) {
      UiStallMonitor.mark('switch to tab #$current');
    }
    _lastShown = current;
    _visited.removeWhere((i) => i >= count);

    return IndexedStack(
      index: current,
      alignment: widget.alignment,
      sizing: widget.sizing,
      children: [
        for (var i = 0; i < count; i++)
          if (_visited.contains(i))
            TickerMode(enabled: i == current, child: widget.children[i])
          else
            const SizedBox.shrink(),
      ],
    );
  }
}
