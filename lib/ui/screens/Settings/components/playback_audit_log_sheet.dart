import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../models/playback_audit_entry.dart';
import '../../../../services/playback_audit_log_service.dart';
import '../../../widgets/snackbar.dart';

class PlaybackAuditLogSheet extends StatefulWidget {
  const PlaybackAuditLogSheet({super.key});

  @override
  State<PlaybackAuditLogSheet> createState() => _PlaybackAuditLogSheetState();
}

class _PlaybackAuditLogSheetState extends State<PlaybackAuditLogSheet> {
  final PlaybackAuditLogService _service = Get.find<PlaybackAuditLogService>();
  List<PlaybackAuditEntry> _entries = const [];
  String? _loadError;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  void _loadEntries() {
    try {
      _entries = _service.recentEntries();
      _loadError = null;
    } catch (_) {
      _entries = const [];
      _loadError = 'Some playback entries could not be read.';
    }
  }

  Future<void> _clear() async {
    if (_clearing || (_entries.isEmpty && _loadError == null)) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear playback audit log?'),
            content: const Text(
              'All recorded playback audit entries will be removed.',
            ),
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
      await _service.clear();
      if (!mounted) return;
      setState(_loadEntries);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'Could not clear playback audit log: $error',
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
        height: MediaQuery.of(context).size.height * .82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Playback audit log',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          '${_entries.length}/500 recent tracks',
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
                    onPressed: () => setState(_loadEntries),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            Expanded(
              child: _entries.isEmpty
                  ? const Center(child: Text('No playback entries yet'))
                  : ListView.separated(
                      itemCount: _entries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        final inLibrary = _isLibraryEntry(entry);
                        return ListTile(
                          dense: true,
                          leading: _LibraryBadge(inLibrary: inLibrary),
                          title: Text(
                            entry.song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${entry.song.artist ?? 'Unknown artist'}\n'
                            '${_timeLabel(entry.playedAt)} · ${entry.source} · ${_flags(entry)}'
                            '${_decision(entry)}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: SizedBox(
                            width: 64,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  inLibrary ? 'Library' : 'External',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium!
                                      .copyWith(
                                        color: inLibrary
                                            ? Colors.green
                                            : Colors.orange,
                                      ),
                                ),
                                if (entry.isCached)
                                  Text(
                                    'Cache',
                                    style:
                                        Theme.of(context).textTheme.labelSmall,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _flags(PlaybackAuditEntry entry) {
    final flags = <String>[
      if (entry.isFavorite) 'favorite',
      if (entry.isDownloaded) 'downloaded',
      if (entry.isCached) 'cache',
      if (entry.inPlaylist) 'playlist',
    ];
    return flags.isEmpty ? 'no library or cache flags' : flags.join(', ');
  }

  bool _isLibraryEntry(PlaybackAuditEntry entry) {
    return entry.isFavorite || entry.isDownloaded || entry.inPlaylist;
  }

  String _decision(PlaybackAuditEntry entry) {
    final source = entry.recommendationSource;
    if (source == null || source.isEmpty) return '';
    final score = entry.recommendationScore;
    final reasons = entry.reasonCodes.take(3).join(', ');
    return '\n$source'
        '${score == null ? '' : ' · ${score.toStringAsFixed(2)}'}'
        '${reasons.isEmpty ? '' : ' · $reasons'}';
  }

  String _timeLabel(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.day)}.${two(time.month)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}

class _LibraryBadge extends StatelessWidget {
  const _LibraryBadge({required this.inLibrary});

  final bool inLibrary;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 17,
      backgroundColor:
          (inLibrary ? Colors.green : Colors.orange).withOpacity(.14),
      child: Icon(
        inLibrary ? Icons.library_music : Icons.public,
        size: 18,
        color: inLibrary ? Colors.green : Colors.orange,
      ),
    );
  }
}
