import 'package:flutter/material.dart';

import '../../models/flow/flow_station.dart';
import 'image_widget.dart';

class FlowStationsWidget extends StatelessWidget {
  const FlowStationsWidget({
    super.key,
    required this.stations,
    required this.onStationTap,
    this.isLoading = false,
  });

  final List<FlowStation> stations;
  final ValueChanged<FlowStation> onStationTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (stations.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 222,
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Flow Stations',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 5),
          Expanded(
            child: Scrollbar(
              thickness: 0,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: stations.length,
                separatorBuilder: (_, __) => const SizedBox(width: 15),
                itemBuilder: (context, index) {
                  final station = stations[index];
                  return _StationCard(
                    station: station,
                    onTap: isLoading ? null : () => onStationTap(station),
                    isLoading: isLoading,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StationCard extends StatelessWidget {
  const _StationCard({
    required this.station,
    required this.onTap,
    required this.isLoading,
  });

  final FlowStation station;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final previewArtist = station.previewSong?.artist?.trim();
    final subtitle = previewArtist != null && previewArtist.isNotEmpty
        ? previewArtist
        : station.tags.take(2).join(', ');

    return Tooltip(
      message: 'Start ${station.title} Flow',
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: isLoading ? .62 : 1,
          child: Container(
            width: 130,
            height: 180,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox.square(
                  dimension: 120,
                  child: Stack(
                    children: [
                      station.previewSong == null
                          ? Container(
                              height: 120,
                              width: 120,
                              decoration: BoxDecoration(
                                color: colors.primaryContainer.withOpacity(.35),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Icon(
                                _iconFor(station.id),
                                color: colors.primary,
                                size: 36,
                              ),
                            )
                          : ImageWidget(
                              song: station.previewSong,
                              size: 120,
                            ),
                      Positioned(
                        right: 7,
                        bottom: 7,
                        child: Container(
                          height: 26,
                          width: 26,
                          decoration: BoxDecoration(
                            color: colors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(.28),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: colors.onPrimary,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  station.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String id) {
    switch (id) {
      case 'cinematic':
        return Icons.movie_filter_outlined;
      case 'gaming_focus':
        return Icons.sports_esports_outlined;
      case 'anime_ost':
        return Icons.auto_awesome_motion_outlined;
      case 'night':
        return Icons.nightlight_round;
      case 'energy':
        return Icons.bolt_outlined;
      case 'chill_focus':
        return Icons.headphones_outlined;
      case 'discover':
        return Icons.explore_outlined;
      default:
        return Icons.auto_awesome;
    }
  }
}
