import 'package:flutter/material.dart';

/// Brand design tokens for Glow Studio.
const Color kBg = Color(0xFF0B0B0F);
const Color kPanel = Color(0xFF17171F);
const Color kPanelHigh = Color(0xFF22222C);
const Color kPink = Color(0xFFFF4D8D);
const Color kViolet = Color(0xFF9B6CFF);
const Color kAmber = Color(0xFFFFB37A);

const LinearGradient kBrandGradient = LinearGradient(
  colors: [kPink, kViolet],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// Full-bleed background with soft, blurred color blobs for depth.
class GlowBackground extends StatelessWidget {
  const GlowBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: kBg)),
        Positioned(top: -130, left: -90, child: _blob(280, kPink.withValues(alpha: 0.30))),
        Positioned(top: 10, right: -120, child: _blob(260, kViolet.withValues(alpha: 0.28))),
        Positioned(bottom: -160, left: -40, child: _blob(320, kViolet.withValues(alpha: 0.16))),
        Positioned(bottom: -60, right: -80, child: _blob(220, kAmber.withValues(alpha: 0.12))),
        child,
      ],
    );
  }

  Widget _blob(double size, Color color) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
          ),
        ),
      );
}

/// A rounded gradient button used for primary actions.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.height = 54,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(height / 2),
          child: Ink(
            height: height,
            decoration: BoxDecoration(
              gradient: kBrandGradient,
              borderRadius: BorderRadius.circular(height / 2),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: kPink.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: expand ? 24 : 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
