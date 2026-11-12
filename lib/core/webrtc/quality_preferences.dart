import 'package:shared_preferences/shared_preferences.dart';
import 'adaptive_quality_controller.dart';

class QualityPreferences {
  static const String _keyQualityPreference = 'ozone_quality_preference';

  /// Returns the default starting tier across ALL platforms (iOS, Android, and macOS):
  /// Crisp 1080p Full HD (1920x1080 @ 30fps) by default.
  static ResolutionTier getDefaultStartingTier() {
    return ResolutionTier.p1080;
  }

  /// Loads saved preference: null means Auto (1080p -> 4K Adaptive), otherwise a fixed ResolutionTier.
  /// Allows all tiers (720p, 1080p, 1440p, 4K) across all platforms.
  static Future<ResolutionTier?> getSavedPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getString(_keyQualityPreference);
      if (val == null || val == 'auto') return null;
      for (final tier in ResolutionTier.values) {
        if (tier.name == val) return tier;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Saves preference: null means Auto, otherwise tier.name (e.g. '1080p', '4K').
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
