import 'package:flutter/material.dart';
import '../core/webrtc/adaptive_quality_controller.dart';
import 'ozone_theme.dart';

class QualityIndicatorWidget extends StatelessWidget {
  final QualityIndicatorState state;

  const QualityIndicatorWidget({super.key, required this.state});

  Color _tierColor(ResolutionTier tier) {
    switch (tier) {
      case ResolutionTier.p4k:
        return OzoneTheme.emerald;
      case ResolutionTier.p1440:
        return OzoneTheme.cyan;
      case ResolutionTier.p1080:
        return OzoneTheme.cyan.withValues(alpha: 0.85);
      case ResolutionTier.p720:
        return OzoneTheme.amber;
    }
  }

  Widget _buildSignalBars(int strength) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (index) {
        final barHeight = 6.0 + (index * 3.5);
        final isActive = index < strength;
        return Container(
          width: 3.5,
          height: barHeight,
          margin: const EdgeInsets.symmetric(horizontal: 1.0),
          decoration: BoxDecoration(
            color: isActive
                ? (strength >= 3
                    ? OzoneTheme.emerald
                    : (strength == 2 ? OzoneTheme.amber : OzoneTheme.ruby))
                : Colors.white24,
            borderRadius: BorderRadius.circular(1.5),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _tierColor(state.tier);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Signal Bars
          _buildSignalBars(state.signalStrength),
          const SizedBox(width: 8),

          // Resolution Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              state.tier.name,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // FPS & RTT
          Text(
            '${state.fps} fps • ${state.rttMs.toInt()}ms',
            style: const TextStyle(
              color: OzoneTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
