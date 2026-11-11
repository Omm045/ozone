import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ozone/core/utils/update_checker.dart';

// Mock HttpClient for simulating GitHub Releases API responses
class MockHttpClient implements HttpClient {
  final int statusCode;
  final String responseBody;
  final bool throwNetworkError;

  MockHttpClient({
    this.statusCode = 200,
    this.responseBody = '{}',
    this.throwNetworkError = false,
  });

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (throwNetworkError) {
      throw const SocketException('Connection refused / network unreachable');
    }
    return MockHttpClientRequest(statusCode, responseBody);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockHttpClientRequest implements HttpClientRequest {
  final int statusCode;
  final String responseBody;

  MockHttpClientRequest(this.statusCode, this.responseBody);

  @override
  final HttpHeaders headers = MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async {
    return MockHttpClientResponse(statusCode, responseBody);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockHttpHeaders implements HttpHeaders {
  final Map<String, Object> _headers = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode;
  final String body;

  MockHttpClientResponse(this.statusCode, this.body);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(utf8.encode(body)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('UpdateChecker Core Version Extraction & Normalization', () {
    test('Correctly extracts version without build suffix from pubspec format "1.0.1+2"', () {
      final normalized = UpdateChecker.normalizeVersion('1.0.1+2');
      expect(normalized, '1.0.1');

      // Also handles leading 'v' with build number
      expect(UpdateChecker.normalizeVersion('v1.0.1+2'), '1.0.1');
      expect(UpdateChecker.normalizeVersion('V1.0.1+99'), '1.0.1');
    });

    test('Correctly strips leading "v" or "V" from GitHub tag_name', () {
      expect(UpdateChecker.normalizeVersion('v1.0.1'), '1.0.1');
      expect(UpdateChecker.normalizeVersion('V1.0.1'), '1.0.1');
      expect(UpdateChecker.normalizeVersion('1.0.1'), '1.0.1');
    });
  });

  group('Required Verification Cases (2.a - 2.e)', () {
    // 2.a: Current "1.0.1", latest tag "v1.0.1" -> result: up to date (no false prompt)
    test('Case 2.a: Current "1.0.1", latest tag "v1.0.1" -> Up to date (no false update prompt)', () {
      final isNewer = UpdateChecker.isVersionNewer('v1.0.1', '1.0.1');
      expect(isNewer, isFalse, reason: 'Matching versions must report up to date');

      // Also verify with pubspec build suffix "1.0.1+2"
      final isNewerWithBuild = UpdateChecker.isVersionNewer('v1.0.1', '1.0.1+2');
      expect(isNewerWithBuild, isFalse, reason: 'Build number "+2" must not cause false update prompt');
    });

    // 2.b: Current "1.0.0", latest tag "v1.0.1" -> result: update available
    test('Case 2.b: Current "1.0.0", latest tag "v1.0.1" -> Update available', () {
      final isNewer = UpdateChecker.isVersionNewer('v1.0.1', '1.0.0');
      expect(isNewer, isTrue, reason: '1.0.1 is newer than 1.0.0');

      final isNewerWithBuild = UpdateChecker.isVersionNewer('v1.0.1', '1.0.0+1');
      expect(isNewerWithBuild, isTrue, reason: '1.0.1 is newer than 1.0.0+1');
    });

    // 2.c: Current "1.0.1", latest tag "v1.0.10" -> result: update available (numeric segment comparison)
    test('Case 2.c: Current "1.0.1", latest tag "v1.0.10" -> Update available (numeric segment comparison: 10 > 1)', () {
      final isNewer = UpdateChecker.isVersionNewer('v1.0.10', '1.0.1');
      expect(isNewer, isTrue, reason: 'Segment 10 must be recognized as greater than 1');

      // Also verify 1.0.2 vs 1.0.10 where naive alphabetical string comparison fails ("1.0.2" > "1.0.10")
      final isNewerThan2 = UpdateChecker.isVersionNewer('v1.0.10', '1.0.2');
      expect(isNewerThan2, isTrue, reason: 'Numeric comparison must treat 1.0.10 as newer than 1.0.2');

      // 1.10.0 vs 1.2.0
      expect(UpdateChecker.isVersionNewer('v1.10.0', '1.2.0'), isTrue);
    });

    // 2.d: Current "1.2.0", latest tag "v1.0.1" -> result: up to date (dev build ahead of release)
    test('Case 2.d: Current "1.2.0", latest tag "v1.0.1" -> Up to date (newer local dev build ahead of published release)', () {
      final isNewer = UpdateChecker.isVersionNewer('v1.0.1', '1.2.0');
      expect(isNewer, isFalse, reason: 'Local build ahead of release must not trigger false downgrade prompt');

      // Local patch ahead: 1.0.2 local vs 1.0.1 published
      expect(UpdateChecker.isVersionNewer('v1.0.1', '1.0.2'), isFalse);

      // Local major ahead: 2.0.0 local vs 1.9.9 published
      expect(UpdateChecker.isVersionNewer('v1.9.9', '2.0.0'), isFalse);
    });

    // 2.e: GitHub API returns no releases yet (404 or empty) -> handled gracefully with error messaging, not a crash
    test('Case 2.e (HTTP 404): GitHub API returns 404 (no releases yet) -> Handled gracefully with noReleases status', () async {
      final mockClient = MockHttpClient(
        statusCode: 404,
        responseBody: '{"message":"Not Found","documentation_url":"https://docs.github.com/rest/releases/releases#get-the-latest-release"}',
      );

      final result = await UpdateChecker.checkForUpdates(
        explicitCurrentVersion: '1.0.1+2',
        customHttpClient: mockClient,
      );

      expect(result.status, UpdateStatus.noReleases);
      expect(result.isUpdateAvailable, isFalse);
      expect(result.errorMessage, contains('No releases published yet'));
    });

    test('Case 2.e (Empty Body): GitHub API returns 200 with empty body -> Handled gracefully without crash', () async {
      final mockClient = MockHttpClient(
        statusCode: 200,
        responseBody: '',
      );

      final result = await UpdateChecker.checkForUpdates(
        explicitCurrentVersion: '1.0.1+2',
        customHttpClient: mockClient,
      );

      expect(result.status, UpdateStatus.noReleases);
      expect(result.isUpdateAvailable, isFalse);
    });

    test('Case 2.e (Missing tag_name): GitHub API returns JSON without tag_name -> Handled gracefully', () async {
      final mockClient = MockHttpClient(
        statusCode: 200,
        responseBody: '{"id": 12345}',
      );

      final result = await UpdateChecker.checkForUpdates(
        explicitCurrentVersion: '1.0.1+2',
        customHttpClient: mockClient,
      );

      expect(result.status, UpdateStatus.noReleases);
      expect(result.isUpdateAvailable, isFalse);
    });

    test('Case 2.e (Network Exception): Network connection drops -> Handled gracefully with error status', () async {
      final mockClient = MockHttpClient(
        throwNetworkError: true,
      );

      final result = await UpdateChecker.checkForUpdates(
        explicitCurrentVersion: '1.0.1+2',
        customHttpClient: mockClient,
      );

      expect(result.status, UpdateStatus.error);
      expect(result.isUpdateAvailable, isFalse);
      expect(result.errorMessage, contains('Network error checking for updates'));
    });
  });

  group('Full API Check & URL Handling Flow', () {
    test('API returns v1.0.1 and current is 1.0.1+2 -> Up to date', () async {
      final mockClient = MockHttpClient(
        statusCode: 200,
        responseBody: jsonEncode({
          'tag_name': 'v1.0.1',
          'html_url': 'https://github.com/Omm045/ozone/releases/tag/v1.0.1',
          'body': 'Initial production release v1.0.1',
        }),
      );

      final result = await UpdateChecker.checkForUpdates(
        explicitCurrentVersion: '1.0.1+2',
        customHttpClient: mockClient,
      );

      expect(result.status, UpdateStatus.upToDate);
      expect(result.isUpdateAvailable, isFalse);
      expect(result.currentVersion, '1.0.1');
      expect(result.latestVersion, '1.0.1');
    });

    test('API returns v1.0.2 and current is 1.0.1+2 -> Update Available with downloadUrl', () async {
      final mockClient = MockHttpClient(
        statusCode: 200,
        responseBody: jsonEncode({
          'tag_name': 'v1.0.2',
          'html_url': 'https://github.com/Omm045/ozone/releases/tag/v1.0.2',
          'body': 'Bug fixes and performance improvements.',
        }),
      );

      final result = await UpdateChecker.checkForUpdates(
        explicitCurrentVersion: '1.0.1+2',
        customHttpClient: mockClient,
      );

      expect(result.status, UpdateStatus.updateAvailable);
      expect(result.isUpdateAvailable, isTrue);
      expect(result.currentVersion, '1.0.1');
      expect(result.latestVersion, '1.0.2');
      expect(result.downloadUrl, 'https://github.com/Omm045/ozone/releases/tag/v1.0.2');
      expect(result.releaseNotes, 'Bug fixes and performance improvements.');
    });
  });
}
