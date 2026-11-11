import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

enum UpdateStatus {
  upToDate,
  updateAvailable,
  noReleases,
  rateLimited,
  error,
}

class UpdateCheckResult {
  final UpdateStatus status;
  final String currentVersion;
  final String? latestVersion;
  final String? releaseNotes;
  final String? downloadUrl;
  final String? errorMessage;

  const UpdateCheckResult({
    required this.status,
    required this.currentVersion,
    this.latestVersion,
    this.releaseNotes,
    this.downloadUrl,
    this.errorMessage,
  });

  bool get isUpdateAvailable => status == UpdateStatus.updateAvailable;
  bool get isUpToDate => status == UpdateStatus.upToDate;
}

class UpdateChecker {
  static const String latestReleaseEndpoint =
      'https://api.github.com/repos/Omm045/ozone/releases/latest';

  /// Normalizes a version string by:
  /// 1. Stripping leading 'v' or 'V' (e.g. "v1.0.1" -> "1.0.1")
  /// 2. Stripping build number / build metadata suffix (e.g. "1.0.1+2" -> "1.0.1")
  static String normalizeVersion(String raw) {
    var v = raw.trim();
    if (v.startsWith('v') || v.startsWith('V')) {
      v = v.substring(1).trim();
    }
    return v.split('+').first.trim();
  }

  /// Compares [latestTag] against [currentVersion] strictly numerically segment-by-segment.
  /// Returns `true` ONLY if [latestTag] is strictly newer than [currentVersion].
  /// Returns `false` if up-to-date or if current is newer (e.g. dev build ahead of release).
  static bool isVersionNewer(String latestTag, String currentVersion) {
    final latestClean = normalizeVersion(latestTag);
    final currentClean = normalizeVersion(currentVersion);

    if (latestClean.isEmpty || currentClean.isEmpty) {
      return false;
    }

    final lSegments = latestClean.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final cSegments = currentClean.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    final maxLen = lSegments.length > cSegments.length ? lSegments.length : cSegments.length;
    while (lSegments.length < maxLen) {
      lSegments.add(0);
    }
    while (cSegments.length < maxLen) {
      cSegments.add(0);
    }

    for (int i = 0; i < maxLen; i++) {
      if (lSegments[i] > cSegments[i]) return true;
      if (lSegments[i] < cSegments[i]) return false;
    }

    return false;
  }

  /// Checks for updates against the GitHub Releases API.
  /// If [explicitCurrentVersion] is not passed, retrieves version from [PackageInfo.fromPlatform()].
  /// Accepts an optional [customHttpClient] for testing.
  static Future<UpdateCheckResult> checkForUpdates({
    String? explicitCurrentVersion,
    HttpClient? customHttpClient,
  }) async {
    String currentVersion;
    if (explicitCurrentVersion != null) {
      currentVersion = normalizeVersion(explicitCurrentVersion);
    } else {
      try {
        final info = await PackageInfo.fromPlatform();
        currentVersion = normalizeVersion(info.version);
      } catch (e) {
        debugPrint('[UpdateChecker] Error fetching PackageInfo: $e. Defaulting to 1.0.1');
        currentVersion = '1.0.1';
      }
    }

    final client = customHttpClient ?? HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.getUrl(Uri.parse(latestReleaseEndpoint));
      request.headers.set('User-Agent', 'Ozone-App');
      request.headers.set('Accept', 'application/vnd.github.v3+json');

      final response = await request.close();

      if (response.statusCode == 404) {
        return UpdateCheckResult(
          status: UpdateStatus.noReleases,
          currentVersion: currentVersion,
          errorMessage: 'No releases published yet on GitHub.',
        );
      }

      if (response.statusCode == 403) {
        return UpdateCheckResult(
          status: UpdateStatus.rateLimited,
          currentVersion: currentVersion,
          errorMessage: 'GitHub API rate limit reached. Please try again in a few minutes.',
        );
      }

      if (response.statusCode != 200) {
        return UpdateCheckResult(
          status: UpdateStatus.error,
          currentVersion: currentVersion,
          errorMessage: 'Could not fetch release information (code ${response.statusCode}).',
        );
      }

      final bodyString = await response.transform(utf8.decoder).join();
      if (bodyString.trim().isEmpty) {
        return UpdateCheckResult(
          status: UpdateStatus.noReleases,
          currentVersion: currentVersion,
          errorMessage: 'Empty response received from GitHub API.',
        );
      }

      final json = jsonDecode(bodyString) as Map<String, dynamic>;
      final rawTagName = (json['tag_name'] as String? ?? '').trim();
      final htmlUrl = (json['html_url'] as String? ?? '').trim();
      final releaseNotes = (json['body'] as String? ?? '').trim();

      if (rawTagName.isEmpty) {
        return UpdateCheckResult(
          status: UpdateStatus.noReleases,
          currentVersion: currentVersion,
          errorMessage: 'No valid release tag found.',
        );
      }

      final latestNormalized = normalizeVersion(rawTagName);
      final hasUpdate = isVersionNewer(latestNormalized, currentVersion);

      return UpdateCheckResult(
        status: hasUpdate ? UpdateStatus.updateAvailable : UpdateStatus.upToDate,
        currentVersion: currentVersion,
        latestVersion: latestNormalized,
        releaseNotes: releaseNotes.isEmpty ? 'Performance improvements and bug fixes.' : releaseNotes,
        downloadUrl: htmlUrl,
      );
    } catch (e) {
      return UpdateCheckResult(
        status: UpdateStatus.error,
        currentVersion: currentVersion,
        errorMessage: 'Network error checking for updates: $e',
      );
    } finally {
      if (customHttpClient == null) {
        client.close();
      }
    }
  }
}
