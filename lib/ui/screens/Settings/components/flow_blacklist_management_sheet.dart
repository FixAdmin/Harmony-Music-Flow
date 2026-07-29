import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../models/flow/blacklist_entry.dart';
import '../../../widgets/snackbar.dart';
import '../settings_screen_controller.dart';

class FlowBlacklistManagementSheet extends StatefulWidget {
  const FlowBlacklistManagementSheet({super.key});

  @override
  State<FlowBlacklistManagementSheet> createState() =>
      _FlowBlacklistManagementSheetState();
}

class _FlowBlacklistManagementSheetState
    extends State<FlowBlacklistManagementSheet> {
  final SettingsScreenController _controller =
      Get.find<SettingsScreenController>();
  final Set<String> _unblocking = {};
  bool _clearing = false;

  List<BlacklistEntry> get _tracks => _controller.activeFlowTrackBlacklist;
  List<BlacklistEntry> get _artists => _controller.activeFlowArtistBlacklist;

  Future<void> _unblock(BlacklistEntry entry) async {
    if (_unblocking.contains(entry.key) || _clearing) return;
    setState(() => _unblocking.add(entry.key));
    try {
      if (entry.type == 'artist') {
        await _controller.unblockFlowArtist(entry.key);
      } else {
        await _controller.unblockFlowTrack(entry.key);
      }
    } catch (error) {
      if (mounted) _showError('Could not unblock entry', error);
    } finally {
      if (mounted) setState(() => _unblocking.remove(entry.key));
    }
  }

  Future<void> _clearAll() async {
    if (_clearing || _tracks.isEmpty && _artists.isEmpty) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear Flow blacklist?'),
            content: const Text(
              'All blocked tracks and artists will be allowed in Flow again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Clear all'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _clearing = true);
    try {
      await _controller.clearFlowBlacklist();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'Flow blacklist cleared', size: SanckBarSize.MEDIUM),
      );
    } catch (error) {
      if (mounted) _showError('Could not clear Flow blacklist', error);
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  void _showError(String message, Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      snackbar(context, '$message: $error', size: SanckBarSize.BIG),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _tracks;
    final artists = _artists;
    final isEmpty = tracks.isEmpty && artists.isEmpty;
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
                          'Flow blacklist',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          '${tracks.length} tracks, ${artists.length} artists',
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
                      tooltip: 'Clear all',
                      onPressed: isEmpty ? null : _clearAll,
                      icon: const Icon(Icons.delete_sweep_outlined),
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
            Expanded(
              child: isEmpty
                  ? const Center(child: Text('No blocked tracks or artists'))
                  : ListView(
                      children: [
                        if (tracks.isNotEmpty) ...[
                          const _SectionLabel('Tracks'),
                          ..._entryTiles(tracks),
                        ],
                        if (artists.isNotEmpty) ...[
                          const _SectionLabel('Artists'),
                          ..._entryTiles(artists),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Iterable<Widget> _entryTiles(List<BlacklistEntry> entries) sync* {
    for (final entry in entries) {
      final busy = _unblocking.contains(entry.key);
      yield ListTile(
        dense: true,
        leading: Icon(entry.type == 'artist' ? Icons.person_off : Icons.block),
        title: Text(
          entry.label.isEmpty ? entry.key : entry.label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle:
            entry.reason == null ? null : Text('Blocked: ${entry.reason}'),
        trailing: SizedBox.square(
          dimension: 40,
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(11),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: 'Unblock',
                  onPressed: _clearing ? null : () => _unblock(entry),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
        ),
      );
      yield const Divider(height: 1, indent: 56);
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
      child: Text(label, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
