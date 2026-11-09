import 'package:flutter/material.dart';

import '../theme.dart';

/// A labeled slider with a value chip that highlights when it is non-neutral.
class AdjustSlider extends StatelessWidget {
  const AdjustSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = -1,
    this.max = 1,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    final display = min < 0
        ? (value * 100).round().toString()
        : (((value - min) / (max - min)) * 100).round().toString();
    final active = (min < 0 && value != 0) || (min >= 0 && value > 0.001);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: active
                      ? kPink.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  display,
                  style: TextStyle(
                    color: active ? kPink : Colors.white38,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
