import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../edit/adjustments.dart';

/// Horizontal strip of live-previewed color-grade presets.
class FilterStrip extends StatelessWidget {
  const FilterStrip({
    super.key,
    required this.preview,
    required this.selected,
    required this.onSelected,
  });

  final Uint8List preview;
  final FilterPreset selected;
  final ValueChanged<FilterPreset> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      itemCount: FilterPreset.values.length,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (context, i) {
        final preset = FilterPreset.values[i];
        final isSelected = preset == selected;
        return GestureDetector(
          onTap: () => onSelected(preset),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? scheme.primary : Colors.white12,
                    width: isSelected ? 2.5 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.4),
                            blurRadius: 14,
                          ),
                        ]
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: ColorFiltered(
                  colorFilter: ColorFilter.matrix(preset.matrix()),
                  child: Image.memory(preview, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                preset.label,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected ? scheme.primary : Colors.white54,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
