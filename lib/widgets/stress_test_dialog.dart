// lib/widgets/stress_test_dialog.dart
//
// Hidden server tool (Ctrl+Shift+Alt+T on the server screen):
//   1. choose the test: Probe, Flood or Both
//   2. watch progress (can be cancelled; test tokens are always removed)
//   3. read the per-device results and where the report files were saved

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../realtime/stress_test_engine.dart';

class StressTestDialog {
  StressTestDialog._();

  static Future<void> show(BuildContext context, StressTestEngine engine, {required int deviceCount}) async {
    final mode = await showDialog<StressMode>(
      context: context,
      builder: (_) => _ChooseDialog(deviceCount: deviceCount),
    );
    if (mode == null || !context.mounted) return;

    var cancelled = false;
    final phase = ValueNotifier<(String, double)>(('Starting…', 0));
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _RunningDialog(phase: phase, onCancel: () => cancelled = true),
    ));

    StressResult? result;
    Object? error;
    try {
      result = await engine.run(
        mode,
        onProgress: (p, v) => phase.value = (p, v),
        isCancelled: () => cancelled,
      );
    } catch (e) {
      error = e;
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close the running dialog
    await showDialog<void>(
      context: context,
      builder: (_) => _ResultDialog(result: result, error: error),
    );
  }
}

class _ChooseDialog extends StatefulWidget {
  final int deviceCount;
  const _ChooseDialog({required this.deviceCount});

  @override
  State<_ChooseDialog> createState() => _ChooseDialogState();
}

class _ChooseDialogState extends State<_ChooseDialog> {
  StressMode _mode = StressMode.probe;
  bool _quiet = false;

  Widget _option(StressMode m, String title, String detail) {
    return RadioListTile<StressMode>(
      value: m,
      groupValue: _mode,
      onChanged: (v) => setState(() => _mode = v ?? _mode),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(detail, style: const TextStyle(fontSize: 12.5)),
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final noDevices = widget.deviceCount == 0;
    final needsQuiet = _mode != StressMode.probe;
    final canStart = !noDevices && (!needsQuiet || _quiet);
    return AlertDialog(
      title: const Text('Network stress test'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              noDevices
                  ? 'No devices are connected to this server, so there is nothing to test.'
                  : '${widget.deviceCount} connected device${widget.deviceCount == 1 ? "" : "s"} will be tested.',
              style: TextStyle(color: noDevices ? Theme.of(context).colorScheme.error : null),
            ),
            const SizedBox(height: 8),
            _option(StressMode.probe, 'Probe (safe, about 20 seconds)',
                'Small test messages to every device. Measures speed and loss. Creates no data.'),
            _option(StressMode.flood, 'Flood (about 20 seconds)',
                '100 test tokens plus 40 request/approval messages to every device. Test tokens appear in the '
                'queues for a few seconds and are deleted automatically.'),
            _option(StressMode.both, 'Both (about 40 seconds)', 'Probe first, then flood.'),
            if (needsQuiet) ...[
              const Divider(height: 20),
              CheckboxListTile(
                value: _quiet,
                onChanged: (v) => setState(() => _quiet = v ?? false),
                title: const Text('No patients are being served right now', style: TextStyle(fontSize: 13)),
                subtitle: const Text('Staff will briefly see test entries on their screens.',
                    style: TextStyle(fontSize: 12)),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
            ],
            const SizedBox(height: 4),
            const Text(
              'Test tokens never reach the cloud, the serial counters or reports. Every device is asked to delete '
              'them at the end, and the report says which ones confirmed.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: canStart ? () => Navigator.pop(context, _mode) : null,
          child: const Text('Start test'),
        ),
      ],
    );
  }
}

class _RunningDialog extends StatelessWidget {
  final ValueNotifier<(String, double)> phase;
  final VoidCallback onCancel;
  const _RunningDialog({required this.phase, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Test running'),
        content: SizedBox(
          width: 420,
          child: ValueListenableBuilder<(String, double)>(
            valueListenable: phase,
            builder: (_, p, __) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.$1),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: p.$2.clamp(0.0, 1.0)),
                const SizedBox(height: 12),
                const Text('Please leave this window open. Cancelling still deletes all test tokens.',
                    style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: onCancel, child: const Text('Cancel test'))],
      ),
    );
  }
}

class _ResultDialog extends StatelessWidget {
  final StressResult? result;
  final Object? error;
  const _ResultDialog({this.result, this.error});

  @override
  Widget build(BuildContext context) {
    final r = result;
    return AlertDialog(
      title: Text(r == null ? 'Test failed' : (r.allPassed ? 'All devices passed' : 'Results')),
      content: SizedBox(
        width: 620,
        child: r == null
            ? Text('The test could not run: $error')
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r.mode.name.toUpperCase()} · ${r.devices.length} devices · ${r.seconds.toStringAsFixed(0)} s'
                        '${r.cancelled ? " · cancelled early" : ""}'),
                    const SizedBox(height: 10),
                    if (r.devices.isEmpty) const Text('No devices were connected.'),
                    for (final d in r.devices) _deviceRow(context, d, r),
                    const SizedBox(height: 10),
                    if (r.savedPaths.isNotEmpty) ...[
                      const Text('Report saved to:', style: TextStyle(fontWeight: FontWeight.w600)),
                      for (final p in r.savedPaths) SelectableText(p, style: const TextStyle(fontSize: 12)),
                    ] else
                      const Text('The report file could not be saved.'),
                  ],
                ),
              ),
      ),
      actions: [
        if (r != null && r.savedPaths.isNotEmpty && Platform.isWindows)
          TextButton(
            onPressed: () => Process.run('explorer.exe', ['/select,', r.savedPaths.first]),
            child: const Text('Show file'),
          ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }

  Widget _deviceRow(BuildContext context, DeviceStress d, StressResult r) {
    final v = d.verdict(r.probeRan, r.floodRan);
    final ok = v.startsWith('PASS');
    final j = d.toJson();
    String rtt(Map<String, dynamic> m) {
      final x = m['rttMs'] as Map<String, dynamic>;
      return 'p95 ${x['p95']} ms · ${m['lossPercent']}% lost';
    }

    final parts = <String>[
      if (r.probeRan) 'probe: ${rtt(j['probe'] as Map<String, dynamic>)}',
      if (r.floodRan) 'tokens: ${rtt(j['flood'] as Map<String, dynamic>)}',
      if (r.floodRan) 'requests: ${rtt(j['requestsApprovals'] as Map<String, dynamic>)}',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('${d.username} (${d.role})  ${d.ip}', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(v,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: ok ? Colors.green.shade700 : Colors.orange.shade800,
                )),
          ]),
          const SizedBox(height: 4),
          for (final p in parts) Text(p, style: const TextStyle(fontSize: 12.5)),
          Text(
            d.lostConnection ? 'connection lost during the test' : (d.reconnected ? 'dropped and reconnected' : 'connection stable'),
            style: const TextStyle(fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
