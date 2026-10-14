// lib/pages/dispensary/widgets/tab_visibility.dart
//
// Keep-alive desk tabs (Hybrid desk, LazyIndexedStack) stay mounted while hidden;
// LazyIndexedStack turns their TickerMode off. These helpers let hidden tabs skip
// Hive-driven rebuilds and refresh once when they are shown again — the clinic PCs
// (i3, 4 GB) were spending CPU rebuilding screens nobody could see.

import 'package:flutter/widgets.dart';

/// Whether [context]'s tab is on screen (no dependency is registered).
bool isTabVisible(BuildContext context) => TickerMode.getValuesNotifier(context).value.enabled;

/// Like a ValueListenableBuilder, but while its tab is hidden it keeps the last
/// built child instead of rebuilding on every change, and rebuilds once when the
/// tab becomes visible again.
class VisibleListenableBuilder extends StatefulWidget {
  final Listenable listenable;
  final WidgetBuilder builder;

  const VisibleListenableBuilder({super.key, required this.listenable, required this.builder});

  @override
  State<VisibleListenableBuilder> createState() => _VisibleListenableBuilderState();
}

class _VisibleListenableBuilderState extends State<VisibleListenableBuilder> {
  Widget? _last;
  bool _stale = true;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(VisibleListenableBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _stale = true;
    if (!identical(oldWidget.listenable, widget.listenable)) {
      oldWidget.listenable.removeListener(_onChanged);
      widget.listenable.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    _stale = true;
    if (mounted && isTabVisible(context)) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Registers the dependency, so showing the tab again triggers a rebuild.
    final visible = TickerMode.valuesOf(context).enabled;
    final last = _last;
    if (!visible && last != null) return last;
    if (_stale || last == null || visible) {
      _last = widget.builder(context);
      _stale = false;
    }
    return _last!;
  }
}
