import 'package:flutter/material.dart';

import '../edit/makeup.dart';
import 'adjust_slider.dart';

/// Controls for landmark-based makeup: lip color + intensity, blush, teeth
/// whitening and eye brightening.
class MakeupControls extends StatelessWidget {
  const MakeupControls({
    super.key,
    required this.makeup,
    required this.onChanged,
  });

  final Makeup makeup;
  final ValueChanged<Makeup> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      children: [
        Row(
          children: [
            const Text('Lips',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(width: 14),
            Expanded(
              child: SizedBox(
                height: 30,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: kLipPalette.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final rgb = kLipPalette[i];
                    final selected = makeup.lipColor == rgb;
                    return GestureDetector(
                      onTap: () {
                        final next = makeup.lipIntensity == 0 ? 0.6 : makeup.lipIntensity;
                        onChanged(makeup.copyWith(lipColor: rgb, lipIntensity: next));
                      },
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Color(0xFF000000 | rgb),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? scheme.primary : Colors.white24,
                            width: selected ? 2.5 : 1,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        AdjustSlider(
          label: 'Lip intensity',
          value: makeup.lipIntensity,
          min: 0,
          max: 1,
          onChanged: (v) => onChanged(makeup.copyWith(lipIntensity: v)),
        ),
        AdjustSlider(
          label: 'Blush',
          value: makeup.blush,
          min: 0,
          max: 1,
          onChanged: (v) => onChanged(makeup.copyWith(blush: v)),
        ),
        AdjustSlider(
          label: 'Teeth whitening',
          value: makeup.teeth,
          min: 0,
          max: 1,
          onChanged: (v) => onChanged(makeup.copyWith(teeth: v)),
        ),
        AdjustSlider(
          label: 'Eye brighten',
          value: makeup.eyeBrighten,
          min: 0,
          max: 1,
          onChanged: (v) => onChanged(makeup.copyWith(eyeBrighten: v)),
        ),
      ],
    );
  }
}
