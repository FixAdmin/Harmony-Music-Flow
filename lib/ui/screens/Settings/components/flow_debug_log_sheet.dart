import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../services/flow/flow_debug_logger.dart';
import '../../../widgets/snackbar.dart';

class FlowDebugLogSheet extends StatefulWidget {
  const FlowDebugLogSheet({super.key});

  @override
  State<FlowDebugLogSheet> createState() => _FlowDebugLogSheetState();
}

class _FlowDebugLogSheetState extends State<FlowDebugLogSheet> {
  final FlowDebugLogger _logger = Get.find<FlowDebugLogger>();
  List<Map<dynamic, dynamic>> _entries = const [];
  String? _loadError;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    try {
      _entries = _logger.entries();
      _loadError = null;
    } catch (_) {
      _entries = const [];
      _loadError = 'The debug log could not be read.';
    }
  }

  Future<void> _clear() async {
    if (_clearing || (_entries.isEmpty && _loadError == null)) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear Flow debug log?'),
            content:
                const Text('Recent Flow decision details will be removed.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _clearing = true);
    try {
      await _logger.clear();
      if (!mounted) return;
      setState(_load);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'Could not clear debug log: $error',
            size: SanckBarSize.BIG),
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .76,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Flow debug log',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          '${_entries.length}/${FlowDebugLogger.maxEntries} decisions',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (_clearing)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: 'Clear log',
                      onPressed: _entries.isEmpty && _loadError == null
                          ? null
                          : _clear,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed:
                        _clearing ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (_loadError != null)
              MaterialBanner(
                content: Text(_loadError!),
                actions: [
                  TextButton(
                    onPressed: () => setState(_load),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            Expanded(
              child: _entries.isEmpty
                  ? Center(
                      child: Text(
                        _loadError == null
                            ? 'No Flow decisions recorded yet'
                            : 'No readable decisions',
                      ),
                    )
                  : ListView.separated(
                      itemCount: _entries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _DebugEntryTile(entry: _entries[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DebugEntryTile extends StatelessWidget {
  const _DebugEntryTile({required this.entry});

  final Map<dynamic, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final title = _text(entry['title'], 'Unknown track');
    final artist = _text(entry['artist'], 'Unknown artist');
    final source = _text(entry['source'], 'unknown source');
    final score = entry['score'] is num
        ? (entry['score'] as num).toDouble().toStringAsFixed(2)
        : null;
    final rawReasons = entry['reasonCodes'];
    final reasons = rawReasons is Iterable
        ? rawReasons.map((reason) => reason.toString()).take(4).join(', ')
        : '';
    return ListTile(
      dense: true,
      leading: const Icon(Icons.auto_awesome_outlined),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '$artist\n${_timeLabel(entry['timestamp'])} · $source'
        '${score == null ? '' : ' · $score'}'
        '${reasons.isEmpty ? '' : '\n$reasons'}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  static String _text(dynamic value, String fallback) {
    return value is String && value.trim().isNotEmpty ? value.trim() : fallback;
  }

  static String _timeLabel(dynamic value) {
    if (value is! int) return 'Unknown time';
    try {
      final time = DateTime.fromMillisecondsSinceEpoch(value);
      String two(int number) => number.toString().padLeft(2, '0');
      return '${two(time.day)}.${two(time.month)} '
          '${two(time.hour)}:${two(time.minute)}';
    } catch (_) {
      return 'Unknown time';
    }
  }
}
