import 'package:shared_preferences/shared_preferences.dart';
import 'adaptive_quality_controller.dart';

class QualityPreferences {
  static const String _keyQualityPreference = 'ozone_quality_preference';

  /// Loads saved preference: null means Auto (default), otherwise a fixed ResolutionTier.
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

  /// Saves preference: null means Auto, otherwise tier.name (e.g. '1080p', '1440p', '4K').
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
