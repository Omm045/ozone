import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'adaptive_quality_controller.dart';

class QualityPreferences {
  static const String _keyQualityPreference = 'ozone_quality_preference';
  static bool? isMobileOverrideForTesting;

  /// Returns the platform-appropriate default starting tier:
  /// 720p HD (1280x720) on mobile (iOS/Android) for AVFoundation/hardware safety,
  /// 1080p Full HD (1920x1080) on desktop.
  static ResolutionTier getDefaultStartingTier() {
    final isMobile = isMobileOverrideForTesting ?? (!kIsWeb && (Platform.isIOS || Platform.isAndroid));
    if (isMobile) {
      return ResolutionTier.p720;
    }
    return ResolutionTier.p1080;
  }

  /// Loads saved preference: null means Auto (default), otherwise a fixed ResolutionTier.
  /// On mobile, clamps to safe tiers (max 720p on iOS, 1080p on Android) even if 4K was previously saved.
  static Future<ResolutionTier?> getSavedPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getString(_keyQualityPreference);
      if (val == null || val == 'auto') return null;
      for (final tier in ResolutionTier.values) {
        if (tier.name == val) {
          final isMobile = isMobileOverrideForTesting ?? (!kIsWeb && (Platform.isIOS || Platform.isAndroid));
          if (isMobile) {
            final isIOS = !kIsWeb && Platform.isIOS;
            if (isIOS && tier != ResolutionTier.p720) {
              return ResolutionTier.p720;
            }
            if (tier == ResolutionTier.p4k || tier == ResolutionTier.p1440) {
              return ResolutionTier.p720;
            }
          }
          return tier;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Saves preference: null means Auto, otherwise tier.name (e.g. '720p', '1080p').
  static Future<void> savePreference(ResolutionTier? tier) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (tier == null) {
        await prefs.setString(_keyQualityPreference, 'auto');
      } else {
        await prefs.setString(_keyQualityPreference, tier.name);
      }
    } catch (_) {}
  }
}
