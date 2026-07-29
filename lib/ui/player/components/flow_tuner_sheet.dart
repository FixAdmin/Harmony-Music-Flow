import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/flow/flow_models.dart';
import '../../../services/flow/flow_station_service.dart';
import '../../../services/flow/flow_tuner.dart';
import '../player_controller.dart';

class FlowTunerSheet extends StatelessWidget {
  const FlowTunerSheet({super.key});

  static const fallbackGenres = [
    'Pop',
    'Rock',
    'Electronic',
    'Hip-Hop',
    'Indie',
    'Metal',
    'Jazz',
    'Classical',
  ];

  @override
  Widget build(BuildContext context) {
    final tuner = Get.find<FlowTuner>();
    final stationService = Get.find<FlowStationService>();
    final playerController = Get.find<PlayerController>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Obx(() {
          final settings = tuner.current.value;
          final genres = <String>{
            ...stationService.stations.expand((station) => station.tags),
            ...settings.genres,
          }.toList();
          if (genres.isEmpty) genres.addAll(fallbackGenres);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Harmony Flow',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reset Flow',
                    onPressed: () => tuner.reset(),
                    icon: const Icon(Icons.restart_alt),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: FlowMode.values
                    .map((mode) => ChoiceChip(
                          label: Text(_modeLabel(mode)),
                          selected: settings.mode == mode,
                          onSelected: (_) {
                            tuner.setMode(mode);
                          },
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              _FlowSlider(
                label: 'New',
                trailing: 'Familiar',
                value: settings.familiarity,
                onChanged: (value) {
                  tuner.setFamiliarity(value);
                },
              ),
              _FlowSlider(
                label: 'Narrow',
                trailing: 'Wide',
                value: settings.variety,
                onChanged: (value) {
                  tuner.setVariety(value);
                },
              ),
              _FlowSlider(
                label: 'Hits',
                trailing: 'Deep cuts',
                value: settings.deepCuts,
                onChanged: (value) {
                  tuner.setDeepCuts(value);
                },
              ),
              const SizedBox(height: 8),
              Text('Genres', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: genres
                    .map((genre) => FilterChip(
                          label: Text(genre),
                          selected: settings.genres.contains(genre),
                          onSelected: (_) {
                            tuner.toggleGenre(genre);
                          },
                        ))
                    .toList(),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: playerController.isFlowStarting.isTrue
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          playerController.applyFlowTuning();
                        },
                  icon: playerController.isFlowStarting.isTrue
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(
                    playerController.isFlowModeOn.isTrue
                        ? 'Apply to Flow'
                        : 'Start Flow',
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  String _modeLabel(FlowMode mode) {
    switch (mode) {
      case FlowMode.auto:
        return 'Auto';
      case FlowMode.chill:
        return 'Chill';
      case FlowMode.energy:
        return 'Energy';
      case FlowMode.melancholy:
        return 'Melancholy';
      case FlowMode.discover:
        return 'Discover';
    }
  }
}

class _FlowSlider extends StatelessWidget {
  const _FlowSlider({
    required this.label,
    required this.trailing,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String trailing;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text(label),
            const Spacer(),
            Text(trailing),
          ],
        ),
        Slider(value: value, onChanged: onChanged),
      ],
    );
  }
}
