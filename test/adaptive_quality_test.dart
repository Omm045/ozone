import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ozone/core/webrtc/adaptive_quality_controller.dart';
import 'package:ozone/core/webrtc/quality_preferences.dart';

void main() {
  group('WebRTC Adaptive Quality Controller Tests', () {
    test('Call starts at 1080p 30fps baseline', () {
      final controller = AdaptiveQualityController();
      expect(controller.currentTier, ResolutionTier.p1080);
      expect(controller.currentTier.width, 1920);
      expect(controller.currentTier.height, 1080);
      expect(controller.currentTier.targetFps, 30);

      final indicator = controller.getCurrentIndicatorState();
      expect(indicator.tier, ResolutionTier.p1080);
      expect(indicator.fps, 30);
    });

    test('Anti-flapping: single bandwidth spike does not step up', () {
      final controller = AdaptiveQualityController(
        initialTier: ResolutionTier.p1080,
        consecutiveGoodSamplesRequired: 3,
      );

      // Single spike sample of 30 Mbps
      const spike = NetworkStatsSample(
        availableBandwidthBps: 30000000,
        roundTripTimeMs: 25.0,
        packetLossRate: 0.0,
        currentFps: 30,
      );

      final action1 = controller.processSample(spike);
      expect(action1, isA<QualityHolding>());
      final holding1 = action1 as QualityHolding;
      expect(holding1.consecutiveGood, 1);
      expect(holding1.required, 3);
      expect(controller.currentTier, ResolutionTier.p1080);

      // Interrupted by an ordinary sample below headroom threshold (< 9 Mbps)
      const normalSample = NetworkStatsSample(
        availableBandwidthBps: 5000000,
        roundTripTimeMs: 40.0,
        packetLossRate: 0.0,
        currentFps: 30,
      );
      final action2 = controller.processSample(normalSample);
      expect(action2, isA<QualityStable>());
      expect(controller.currentTier, ResolutionTier.p1080);
      expect(controller.consecutiveGoodSamples, 0);

      // Subsequent spike starts streak from 1 again
      final action3 = controller.processSample(spike);
      expect(action3, isA<QualityHolding>());
      expect((action3 as QualityHolding).consecutiveGood, 1);
      expect(controller.currentTier, ResolutionTier.p1080);
    });

    test('Sustained headroom over 3 consecutive samples steps up to 1440p and 4K', () {
      final controller = AdaptiveQualityController(
        initialTier: ResolutionTier.p1080,
        consecutiveGoodSamplesRequired: 3,
      );

      final tierChanges = <ResolutionTier>[];
      controller.onTierChanged = (tier) => tierChanges.add(tier);

      const good1440pSample = NetworkStatsSample(
        availableBandwidthBps: 12000000, // 12 Mbps (> 9 Mbps headroom)
        roundTripTimeMs: 30.0,
        packetLossRate: 0.005,
        currentFps: 30,
      );

      // Sample 1: holding 1/3
      expect(controller.processSample(good1440pSample), const QualityHolding(consecutiveGood: 1, required: 3));
      expect(controller.currentTier, ResolutionTier.p1080);

      // Sample 2: holding 2/3
      expect(controller.processSample(good1440pSample), const QualityHolding(consecutiveGood: 2, required: 3));
      expect(controller.currentTier, ResolutionTier.p1080);

      // Sample 3: step up to 1440p!
      final stepUp1 = controller.processSample(good1440pSample);
      expect(stepUp1, isA<QualitySteppedUp>());
      expect(controller.currentTier, ResolutionTier.p1440);
      expect(tierChanges, [ResolutionTier.p1440]);

      // Now simulate 3 consecutive samples with 4K headroom (> 18 Mbps)
      const good4kSample = NetworkStatsSample(
        availableBandwidthBps: 25000000, // 25 Mbps (> 18 Mbps headroom)
        roundTripTimeMs: 20.0,
        packetLossRate: 0.001,
        currentFps: 30,
      );

      expect(controller.processSample(good4kSample), const QualityHolding(consecutiveGood: 1, required: 3));
      expect(controller.processSample(good4kSample), const QualityHolding(consecutiveGood: 2, required: 3));
      final stepUp2 = controller.processSample(good4kSample);
      expect(stepUp2, isA<QualitySteppedUp>());
      expect(controller.currentTier, ResolutionTier.p4k);
      expect(controller.currentTier.width, 3840);
      expect(controller.currentTier.height, 2160);
      expect(tierChanges, [ResolutionTier.p1440, ResolutionTier.p4k]);
    });

    test('Smooth step-down on degradation without dropping the call', () {
      final controller = AdaptiveQualityController(initialTier: ResolutionTier.p4k);

      // 1. Packet loss degradation (6% loss)
      const lossSample = NetworkStatsSample(
        availableBandwidthBps: 20000000,
        roundTripTimeMs: 40.0,
        packetLossRate: 0.06,
        currentFps: 30,
      );
      final stepDown1 = controller.processSample(lossSample);
      expect(stepDown1, isA<QualitySteppedDown>());
      expect((stepDown1 as QualitySteppedDown).from, ResolutionTier.p4k);
      expect(stepDown1.to, ResolutionTier.p1440);
      expect(controller.currentTier, ResolutionTier.p1440);

      // 2. Bandwidth drop below target (< 7.0 Mbps * 0.85 = 5.95 Mbps)
      const lowBandwidthSample = NetworkStatsSample(
        availableBandwidthBps: 4000000, // 4.0 Mbps
        roundTripTimeMs: 50.0,
        packetLossRate: 0.0,
        currentFps: 30,
      );
      final stepDown2 = controller.processSample(lowBandwidthSample);
      expect(stepDown2, isA<QualitySteppedDown>());
      expect((stepDown2 as QualitySteppedDown).from, ResolutionTier.p1440);
      expect(stepDown2.to, ResolutionTier.p1080);
      expect(controller.currentTier, ResolutionTier.p1080);

      // 3. High RTT latency degradation (> 250ms)
      const highLatencySample = NetworkStatsSample(
        availableBandwidthBps: 3000000,
        roundTripTimeMs: 310.0,
        packetLossRate: 0.0,
        currentFps: 28,
      );
      final stepDown3 = controller.processSample(highLatencySample);
      expect(stepDown3, isA<QualitySteppedDown>());
      expect((stepDown3 as QualitySteppedDown).from, ResolutionTier.p1080);
      expect(stepDown3.to, ResolutionTier.p720);
      expect(controller.currentTier, ResolutionTier.p720);

      // 4. At 720p floor, further degradation remains stable at 720p without crashing
      final floorAction = controller.processSample(highLatencySample);
      expect(floorAction, isA<QualityStable>());
      expect(controller.currentTier, ResolutionTier.p720);
    });

    test('Signal strength mapping in QualityIndicatorState', () {
      const excellent = QualityIndicatorState(
        tier: ResolutionTier.p4k,
        fps: 30,
        rttMs: 30,
        bandwidthMbps: 20.0,
        packetLossPercent: 0.0,
      );
      expect(excellent.signalStrength, 4);

      const good = QualityIndicatorState(
        tier: ResolutionTier.p1080,
        fps: 30,
        rttMs: 60,
        bandwidthMbps: 5.0,
        packetLossPercent: 0.5,
      );
      expect(good.signalStrength, 3);

      const fair = QualityIndicatorState(
        tier: ResolutionTier.p1080,
        fps: 28,
        rttMs: 140,
        bandwidthMbps: 3.0,
        packetLossPercent: 2.5,
      );
      expect(fair.signalStrength, 2);

      const poor = QualityIndicatorState(
        tier: ResolutionTier.p720,
        fps: 20,
        rttMs: 320,
        bandwidthMbps: 1.0,
        packetLossPercent: 6.0,
      );
      expect(poor.signalStrength, 1);
    });

    test(
      'Manual tier selection locks controller and ignores step up/down samples; switching back to Auto resumes adaptation',
      () {
        final controller = AdaptiveQualityController(
          initialTier: ResolutionTier.p1080,
          consecutiveGoodSamplesRequired: 2,
        );

        final tierEvents = <ResolutionTier>[];
        controller.onTierChanged = (tier) => tierEvents.add(tier);

        expect(controller.isAuto, isTrue);
        expect(controller.currentTier, ResolutionTier.p1080);

        // 1. Manually lock to 1080p
        controller.setManualTier(ResolutionTier.p1080);
        expect(controller.isAuto, isFalse);
        expect(controller.manualTier, ResolutionTier.p1080);
        expect(controller.currentTier, ResolutionTier.p1080);
        expect(tierEvents, [ResolutionTier.p1080]);

        // 2. Feed sustained 4K headroom (> 25 Mbps) — controller MUST ignore and remain locked at 1080p
        const hugeHeadroom = NetworkStatsSample(
          availableBandwidthBps: 30000000,
          roundTripTimeMs: 20.0,
          packetLossRate: 0.0,
          currentFps: 30,
        );

        for (int i = 0; i < 5; i++) {
          final action = controller.processSample(hugeHeadroom);
          expect(action, isA<QualityStable>());
          expect(controller.currentTier, ResolutionTier.p1080);
        }
        // No additional tier changes occurred
        expect(tierEvents, [ResolutionTier.p1080]);

        // 3. Feed severe degradation (6% loss, 350ms RTT) — controller MUST ignore and not step down
        const degradedSample = NetworkStatsSample(
          availableBandwidthBps: 500000,
          roundTripTimeMs: 350.0,
          packetLossRate: 0.06,
          currentFps: 15,
        );

        for (int i = 0; i < 5; i++) {
          final action = controller.processSample(degradedSample);
          expect(action, isA<QualityStable>());
          expect(controller.currentTier, ResolutionTier.p1080);
        }

        // 4. Switch manual tier to 4K
        controller.setManualTier(ResolutionTier.p4k);
        expect(controller.isAuto, isFalse);
        expect(controller.currentTier, ResolutionTier.p4k);
        expect(tierEvents, [ResolutionTier.p1080, ResolutionTier.p4k]);

        // Feed degradation — stays locked at 4K
        expect(controller.processSample(degradedSample), isA<QualityStable>());
        expect(controller.currentTier, ResolutionTier.p4k);

        // 5. Switch back to Auto
        controller.setManualTier(null);
        expect(controller.isAuto, isTrue);
        expect(controller.manualTier, isNull);

        // Now from the next sample onward, normal adaptive behavior resumes:
        // Degradation causes step down from 4K to 1440p
        final stepDownAction = controller.processSample(degradedSample);
        expect(stepDownAction, isA<QualitySteppedDown>());
        expect(controller.currentTier, ResolutionTier.p1440);
        expect(tierEvents, [ResolutionTier.p1080, ResolutionTier.p4k, ResolutionTier.p1440]);
      },
    );

    test('QualityIndicatorState reflects isAuto correctly', () {
      final controller = AdaptiveQualityController(initialTier: ResolutionTier.p1080);

      // Auto mode
      final autoIndicator = controller.getCurrentIndicatorState();
      expect(autoIndicator.isAuto, isTrue);
      expect(autoIndicator.tier, ResolutionTier.p1080);

      // Manual mode
      controller.setManualTier(ResolutionTier.p1440);
      final manualIndicator = controller.getCurrentIndicatorState();
      expect(manualIndicator.isAuto, isFalse);
      expect(manualIndicator.tier, ResolutionTier.p1440);
    });

    test('QualityPreferences persists preference across sessions', () async {
      SharedPreferences.setMockInitialValues({});

      // Initial state is Auto (null)
      final initial = await QualityPreferences.getSavedPreference();
      expect(initial, isNull);

      // Save fixed 1440p tier
      await QualityPreferences.savePreference(ResolutionTier.p1440);
      final saved1440 = await QualityPreferences.getSavedPreference();
      expect(saved1440, ResolutionTier.p1440);

      // Save fixed 4K tier
      await QualityPreferences.savePreference(ResolutionTier.p4k);
      final saved4k = await QualityPreferences.getSavedPreference();
      expect(saved4k, ResolutionTier.p4k);

      // Switch back to Auto
      await QualityPreferences.savePreference(null);
      final savedAuto = await QualityPreferences.getSavedPreference();
      expect(savedAuto, isNull);
    });
  });
}
