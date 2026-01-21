import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../accurate_step_counter_impl.dart';
import '../models/step_record.dart';
import '../models/step_record_source.dart';

/// A reusable widget that displays step logs for debugging purposes.
///
/// This widget provides:
/// - Real-time log updates via stream
/// - Filtering by source (foreground/background/terminated/external)
/// - Date range filtering
/// - Export to clipboard functionality
/// - Color-coded entries by source
///
/// Example:
/// ```dart
/// StepLogsViewer(
///   stepCounter: _stepCounter,
///   maxHeight: 400,
///   showFilters: true,
/// )
/// ```
class StepLogsViewer extends StatefulWidget {
  /// The step counter instance to get logs from
  final AccurateStepCounterImpl stepCounter;

  /// Maximum height of the viewer. If null, takes available space.
  final double? maxHeight;

  /// Whether to show filter buttons
  final bool showFilters;

  /// Whether to show export button
  final bool showExportButton;

  /// Whether to show date range picker
  final bool showDatePicker;

  /// Background color of the log container
  final Color? backgroundColor;

  /// Text style for log entries
  final TextStyle? textStyle;

  /// Number of logs to display (default: 100)
  final int maxLogs;

  /// Whether to auto-scroll to new logs
  final bool autoScroll;

  const StepLogsViewer({
    super.key,
    required this.stepCounter,
    this.maxHeight,
    this.showFilters = true,
    this.showExportButton = true,
    this.showDatePicker = true,
    this.backgroundColor,
    this.textStyle,
    this.maxLogs = 100,
    this.autoScroll = true,
  });

  @override
  State<StepLogsViewer> createState() => _StepLogsViewerState();
}

class _StepLogsViewerState extends State<StepLogsViewer> {
  List<StepRecord> _logs = [];
  StepRecordSource? _selectedSource;
  DateTime? _startDate;
  DateTime? _endDate;
  StreamSubscription<List<StepRecord>>? _logsSubscription;
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _subscribeToLogs();
  }

  @override
  void dispose() {
    _logsSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    try {
      final logs = await widget.stepCounter.getStepLogs(
        from: _startDate,
        to: _endDate,
        source: _selectedSource,
      );
      setState(() {
        _logs = logs.take(widget.maxLogs).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _subscribeToLogs() {
    _logsSubscription = widget.stepCounter
        .watchStepLogs(from: _startDate, to: _endDate, source: _selectedSource)
        .listen((logs) {
          if (mounted) {
            setState(() {
              _logs = logs.take(widget.maxLogs).toList();
            });
            if (widget.autoScroll && _scrollController.hasClients) {
              Future.delayed(const Duration(milliseconds: 100), () {
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  );
                }
              });
            }
          }
        });
  }

  void _applyFilter(StepRecordSource? source) {
    setState(() => _selectedSource = source);
    _logsSubscription?.cancel();
    _loadLogs();
    _subscribeToLogs();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 7)),
              end: now,
            ),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end.add(const Duration(days: 1));
      });
      _logsSubscription?.cancel();
      _loadLogs();
      _subscribeToLogs();
    }
  }

  void _clearDateFilter() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
    _logsSubscription?.cancel();
    _loadLogs();
    _subscribeToLogs();
  }

  Future<void> _exportLogs() async {
    final buffer = StringBuffer();
    buffer.writeln('Step Logs Export - ${DateTime.now()}');
    buffer.writeln('=' * 50);
    buffer.writeln('');

    for (final log in _logs) {
      buffer.writeln('Steps: ${log.stepCount}');
      buffer.writeln('From: ${log.fromTime}');
      buffer.writeln('To: ${log.toTime}');
      buffer.writeln('Source: ${log.source.name}');
      buffer.writeln('Rate: ${log.stepsPerSecond.toStringAsFixed(2)}/s');
      buffer.writeln('-' * 30);
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logs copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Color _getSourceColor(StepRecordSource source) {
    switch (source) {
      case StepRecordSource.foreground:
        return Colors.green;
      case StepRecordSource.background:
        return Colors.orange;
      case StepRecordSource.terminated:
        return Colors.red;
      case StepRecordSource.external:
        return Colors.blue;
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = widget.backgroundColor ?? Colors.black;
    final defaultTextStyle =
        widget.textStyle ??
        const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: Colors.greenAccent,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header with title and actions
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Text(
                'Step Logs',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${_logs.length} entries',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              if (widget.showExportButton) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: _logs.isEmpty ? null : _exportLogs,
                  tooltip: 'Copy to clipboard',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
        ),

        // Filter chips
        if (widget.showFilters)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _selectedSource == null,
                  onSelected: (_) => _applyFilter(null),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                FilterChip(
                  label: const Text('FG'),
                  selected: _selectedSource == StepRecordSource.foreground,
                  onSelected: (_) => _applyFilter(StepRecordSource.foreground),
                  visualDensity: VisualDensity.compact,
                  selectedColor: Colors.green.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 4),
                FilterChip(
                  label: const Text('BG'),
                  selected: _selectedSource == StepRecordSource.background,
                  onSelected: (_) => _applyFilter(StepRecordSource.background),
                  visualDensity: VisualDensity.compact,
                  selectedColor: Colors.orange.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 4),
                FilterChip(
                  label: const Text('Term'),
                  selected: _selectedSource == StepRecordSource.terminated,
                  onSelected: (_) => _applyFilter(StepRecordSource.terminated),
                  visualDensity: VisualDensity.compact,
                  selectedColor: Colors.red.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 4),
                FilterChip(
                  label: const Text('Ext'),
                  selected: _selectedSource == StepRecordSource.external,
                  onSelected: (_) => _applyFilter(StepRecordSource.external),
                  visualDensity: VisualDensity.compact,
                  selectedColor: Colors.blue.withValues(alpha: 0.3),
                ),
                if (widget.showDatePicker) ...[
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      _startDate != null
                          ? '${_formatDate(_startDate!)} - ${_formatDate(_endDate!)}'
                          : 'Date',
                    ),
                    onPressed: _pickDateRange,
                    visualDensity: VisualDensity.compact,
                  ),
                  if (_startDate != null) ...[
                    const SizedBox(width: 4),
                    ActionChip(
                      avatar: const Icon(Icons.clear, size: 16),
                      label: const Text('Clear'),
                      onPressed: _clearDateFilter,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ],
            ),
          ),

        const SizedBox(height: 8),

        // Logs container
        Container(
          height: widget.maxHeight,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _logs.isEmpty
              ? Center(
                  child: Text(
                    'No logs found',
                    style: defaultTextStyle.copyWith(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[_logs.length - 1 - index];
                    final sourceColor = _getSourceColor(log.source);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Timestamp
                          Text(
                            '[${_formatTime(log.fromTime)}]',
                            style: defaultTextStyle.copyWith(
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Source badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: sourceColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              log.source.name.substring(0, 2).toUpperCase(),
                              style: defaultTextStyle.copyWith(
                                color: sourceColor,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Step count
                          Text(
                            '+${log.stepCount}',
                            style: defaultTextStyle.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Rate
                          Text(
                            '(${log.stepsPerSecond.toStringAsFixed(1)}/s)',
                            style: defaultTextStyle.copyWith(
                              color: Colors.grey[600],
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
