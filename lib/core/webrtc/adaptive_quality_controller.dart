enum ResolutionTier {
  p720(
    name: '720p',
    width: 1280,
    height: 720,
    targetFps: 30,
    targetBitrateBps: 2000000,
    minHeadroomForStepUpBps: 4000000,
    scaleResolutionDownBy: 1.5,
  ),
  p1080(
    name: '1080p',
    width: 1920,
    height: 1080,
    targetFps: 30,
    targetBitrateBps: 5000000,
    minHeadroomForStepUpBps: 9000000,
    scaleResolutionDownBy: 1.0,
  ),
  p1440(
    name: '1440p',
    width: 2560,
    height: 1440,
    targetFps: 30,
    targetBitrateBps: 10000000,
    minHeadroomForStepUpBps: 18000000,
    scaleResolutionDownBy: 1.0,
  ),
  p4k(
    name: '4K',
    width: 3840,
    height: 2160,
    targetFps: 30,
    targetBitrateBps: 25000000, // 25 Mbps target taking advantage of high-bandwidth (up to 100 Mbps) connections
    minHeadroomForStepUpBps: 999999999,
    scaleResolutionDownBy: 1.0,
  );

  final String name;
  final int width;
  final int height;
  final int targetFps;
  final int targetBitrateBps;
  final int minHeadroomForStepUpBps;
  final double scaleResolutionDownBy;

  const ResolutionTier({
    required this.name,
    required this.width,
    required this.height,
    required this.targetFps,
    required this.targetBitrateBps,
    required this.minHeadroomForStepUpBps,
    required this.scaleResolutionDownBy,
  });

  ResolutionTier? get nextHigher {
    switch (this) {
      case ResolutionTier.p720:
        return ResolutionTier.p1080;
      case ResolutionTier.p1080:
        return ResolutionTier.p1440;
      case ResolutionTier.p1440:
        return ResolutionTier.p4k;
      case ResolutionTier.p4k:
        return null;
    }
  }

  ResolutionTier? get nextLower {
    switch (this) {
      case ResolutionTier.p4k:
        return ResolutionTier.p1440;
      case ResolutionTier.p1440:
        return ResolutionTier.p1080;
      case ResolutionTier.p1080:
        return ResolutionTier.p720;
      case ResolutionTier.p720:
        return null;
    }
  }

  bool operator >(ResolutionTier other) => index > other.index;
  bool operator <(ResolutionTier other) => index < other.index;
  bool operator >=(ResolutionTier other) => index >= other.index;
  bool operator <=(ResolutionTier other) => index <= other.index;
}

class NetworkStatsSample {
  final double availableBandwidthBps;
  final double roundTripTimeMs;
  final double packetLossRate;
  final int currentFps;

  const NetworkStatsSample({
    required this.availableBandwidthBps,
    required this.roundTripTimeMs,
    this.packetLossRate = 0.0,
    this.currentFps = 30,
  });
}

abstract class QualityAction {
  const QualityAction();
}

class QualityStable extends QualityAction {
  const QualityStable();

  @override
  bool operator ==(Object other) => other is QualityStable;

  @override
  int get hashCode => 0;
}

class QualityHolding extends QualityAction {
  final int consecutiveGood;
  final int required;

  const QualityHolding({required this.consecutiveGood, required this.required});

  @override
  bool operator ==(Object other) =>
      other is QualityHolding &&
      other.consecutiveGood == consecutiveGood &&
      other.required == required;

  @override
  int get hashCode => Object.hash(consecutiveGood, required);
}

class QualitySteppedUp extends QualityAction {
  final ResolutionTier from;
  final ResolutionTier to;

  const QualitySteppedUp({required this.from, required this.to});

  @override
  bool operator ==(Object other) =>
      other is QualitySteppedUp && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

class QualitySteppedDown extends QualityAction {
  final ResolutionTier from;
  final ResolutionTier to;
  final String reason;

  const QualitySteppedDown({
    required this.from,
    required this.to,
    required this.reason,
  });

  @override
  bool operator ==(Object other) =>
      other is QualitySteppedDown &&
      other.from == from &&
      other.to == to &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(from, to, reason);
}

class QualityIndicatorState {
  final ResolutionTier tier;
  final int fps;
  final double rttMs;
  final double bandwidthMbps;
  final double packetLossPercent;
  final bool isAuto;

  const QualityIndicatorState({
    this.tier = ResolutionTier.p1080,
    this.fps = 30,
    this.rttMs = 45.0,
    this.bandwidthMbps = 5.0,
    this.packetLossPercent = 0.0,
    this.isAuto = true,
  });

  int get signalStrength {
    if (rttMs > 250 || packetLossPercent > 5.0) {
      return 1; // Poor
    } else if (rttMs > 120 || packetLossPercent > 2.0) {
      return 2; // Fair
    } else if (tier >= ResolutionTier.p1440) {
      return 4; // Excellent (HD/4K)
    } else {
      return 3; // Good
    }
  }
}

class AdaptiveQualityController {
  ResolutionTier _currentTier;
  ResolutionTier? _manualTier;
  final int consecutiveGoodSamplesRequired;
  bool deviceSupports60Fps = false;

  int _consecutiveGoodSamples = 0;
  NetworkStatsSample? _lastSample;
  void Function(ResolutionTier)? onTierChanged;

  AdaptiveQualityController({
    ResolutionTier initialTier = ResolutionTier.p1080,
    this.consecutiveGoodSamplesRequired = 3,
    ResolutionTier? manualTier,
    this.deviceSupports60Fps = false,
  })  : _currentTier = manualTier ?? initialTier,
        _manualTier = manualTier;

  ResolutionTier get currentTier => _currentTier;
  ResolutionTier? get manualTier => _manualTier;
  bool get isAuto => _manualTier == null;
  int get consecutiveGoodSamples => _consecutiveGoodSamples;

  int get currentTargetFps =>
      (deviceSupports60Fps && _currentTier >= ResolutionTier.p1080) ? 60 : 30;

  void setManualTier(ResolutionTier? tier) {
    _manualTier = tier;
    _consecutiveGoodSamples = 0;
    if (tier != null) {
      _currentTier = tier;
      onTierChanged?.call(tier);
    }
  }

  QualityAction processSample(NetworkStatsSample sample) {
    _lastSample = sample;

    // When manually locked to a fixed tier, respect that tier as both ceiling and floor.
    if (_manualTier != null) {
      return const QualityStable();
    }

    // 1. Evaluate degradation first (smooth step down, never freeze/drop)
    final degradation = _evaluateDegradation(sample);
    if (degradation.shouldStepDown) {
      _consecutiveGoodSamples = 0;
      final lower = _currentTier.nextLower;
      if (lower != null) {
        final prev = _currentTier;
        _currentTier = lower;
        onTierChanged?.call(lower);
        return QualitySteppedDown(
          from: prev,
          to: lower,
          reason: degradation.reason,
        );
      } else {
        return const QualityStable(); // Already at safe floor (720p)
      }
    }

    // 2. Evaluate sustained headroom for step-up
    final higher = _currentTier.nextHigher;
    if (higher == null) {
      _consecutiveGoodSamples = 0;
      return const QualityStable(); // At 4K
    }

    if (_hasHeadroom(sample)) {
      _consecutiveGoodSamples++;
      if (_consecutiveGoodSamples >= consecutiveGoodSamplesRequired) {
        _consecutiveGoodSamples = 0;
        final prev = _currentTier;
        _currentTier = higher;
        onTierChanged?.call(higher);
        return QualitySteppedUp(from: prev, to: higher);
      } else {
        return QualityHolding(
          consecutiveGood: _consecutiveGoodSamples,
          required: consecutiveGoodSamplesRequired,
        );
      }
    } else {
      // Interrupted headroom streak -> reset counter to avoid flapping
      _consecutiveGoodSamples = 0;
      return const QualityStable();
    }
  }

  QualityIndicatorState getCurrentIndicatorState() {
    final sample = _lastSample ??
        NetworkStatsSample(
          availableBandwidthBps: _currentTier.targetBitrateBps.toDouble(),
          roundTripTimeMs: 40.0,
          currentFps: currentTargetFps,
        );

    return QualityIndicatorState(
      tier: _currentTier,
      fps: sample.currentFps > 0 ? sample.currentFps : currentTargetFps,
      rttMs: sample.roundTripTimeMs,
      bandwidthMbps: sample.availableBandwidthBps / 1000000.0,
      packetLossPercent: sample.packetLossRate * 100.0,
      isAuto: isAuto,
    );
  }

  ({bool shouldStepDown, String reason}) _evaluateDegradation(
    NetworkStatsSample sample,
  ) {
    if (sample.packetLossRate > 0.04) {
      return (
        shouldStepDown: true,
        reason: 'High packet loss (${(sample.packetLossRate * 100).toStringAsFixed(1)}%)',
      );
    }
    if (sample.roundTripTimeMs > 250.0) {
      return (
        shouldStepDown: true,
        reason: 'High RTT (${sample.roundTripTimeMs.toInt()}ms)',
      );
    }
    final minBandwidth = _currentTier.targetBitrateBps * 0.85;
    if (sample.availableBandwidthBps < minBandwidth) {
      return (
        shouldStepDown: true,
        reason:
            'Bandwidth dropped below target (${(sample.availableBandwidthBps / 1000000).toStringAsFixed(1)} Mbps)',
      );
    }
    return (shouldStepDown: false, reason: '');
  }

  bool _hasHeadroom(NetworkStatsSample sample) {
    if (sample.availableBandwidthBps < _currentTier.minHeadroomForStepUpBps) {
      return false;
    }
    if (sample.roundTripTimeMs > 120.0) return false;
    if (sample.packetLossRate > 0.015) return false;
    if (sample.currentFps < 25) return false;
    return true;
  }
}
