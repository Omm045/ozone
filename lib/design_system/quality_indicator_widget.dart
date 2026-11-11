import 'package:flutter/material.dart';
import '../core/webrtc/adaptive_quality_controller.dart';
import '../core/webrtc/webrtc_call_manager.dart';
import 'ozone_theme.dart';

class QualityIndicatorWidget extends StatelessWidget {
  final QualityIndicatorState state;
  final VoidCallback? onTap;
  final WebRtcCallManager? callManager;

  const QualityIndicatorWidget({
    super.key,
    required this.state,
    this.onTap,
    this.callManager,
  });

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
            color: isActive ? OzoneTheme.emerald : Colors.white24,
            borderRadius: BorderRadius.circular(1.5),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (onTap != null) {
          onTap!();
        } else {
          showConnectionStatsModal(context, state, callManager: callManager);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: OzoneTheme.emerald.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSignalBars(state.signalStrength),
            const SizedBox(width: 8),
            Text(
              state.tier.name,
              style: const TextStyle(
                color: OzoneTheme.emerald,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showConnectionStatsModal(
  BuildContext context,
  QualityIndicatorState initialState, {
  WebRtcCallManager? callManager,
}) {
  showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (dialogCtx) {
      Widget buildContent(QualityIndicatorState currentState) {
        final telemetry = currentState.telemetry;
        final isRelay = telemetry.routeType.toLowerCase().contains('relay');
        final routeColor = isRelay ? OzoneTheme.amber : OzoneTheme.emerald;
        final qualityColor = currentState.signalStrength >= 3
            ? OzoneTheme.emerald
            : (currentState.signalStrength == 2 ? OzoneTheme.amber : OzoneTheme.ruby);

        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 380),
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: OzoneTheme.statsCard.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12, width: 1),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 28,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header: Signal icon + "Connection" on left, quality status in green on right
                  Row(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(4, (i) {
                          return Container(
                            width: 3.5,
                            height: 6.0 + (i * 3.5),
                            margin: const EdgeInsets.symmetric(horizontal: 1.0),
                            decoration: BoxDecoration(
                              color: OzoneTheme.emerald,
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Connection',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: OzoneTheme.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        telemetry.qualityStatus,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: qualityColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 12),

                  // Telemetry Rows
                  _buildTelemetryRow('Sending:', '${telemetry.sendingBitrateKbps} kbps'),
                  _buildTelemetryRow('Receiving:', '${telemetry.receivingBitrateKbps} kbps'),
                  _buildTelemetryRow(
                    'Picture sent:',
                    '${telemetry.sentResolution} at ${telemetry.sentFps} fps',
                  ),
                  _buildTelemetryRow(
                    'Picture received:',
                    '${telemetry.receivedResolution} at ${telemetry.receivedFps} fps',
                  ),
                  _buildTelemetryRow('Delay (round trip):', '${telemetry.roundTripTimeMs} ms'),
                  _buildTelemetryRow(
                    'Packet loss:',
                    '${telemetry.packetLossPercent.toStringAsFixed(1)} %',
                  ),
                  _buildTelemetryRow('Jitter:', '${telemetry.jitterMs} ms'),
                  _buildTelemetryRow(
                    'Route:',
                    telemetry.routeType,
                    valueColor: routeColor,
                  ),
                  _buildTelemetryRow('State:', telemetry.connectionState),

                  const SizedBox(height: 16),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 12),

                  // Footer: "Updates every 2 seconds. Tap to close."
                  InkWell(
                    onTap: () => Navigator.of(dialogCtx).pop(),
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Updates every 2 seconds. Tap to close.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      if (callManager != null) {
        return ListenableBuilder(
          listenable: callManager,
          builder: (context, _) => buildContent(callManager.qualityState),
        );
      }

      return buildContent(initialState);
    },
  );
}

Widget _buildTelemetryRow(String label, String value, {Color valueColor = Colors.white}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4.5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: OzoneTheme.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ),
      ],
    ),
  );
}
