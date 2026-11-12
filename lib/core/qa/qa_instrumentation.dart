// QA-ONLY instrumentation. Compiled in only with --dart-define=QA=true.
//
// Every call site is guarded by `if (kQaBuild)`, a compile-time constant, so
// in normal and release builds the guarded code (and this file's strings) is
// tree-shaken away. Phase 5 verifies the release binaries contain no
// 'QA_STATS' / 'QA_EVENT' strings.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

const bool kQaBuild = bool.fromEnvironment('QA');
const int kQaStatsMs = int.fromEnvironment('QA_STATS_MS', defaultValue: 1000);

/// Test-side handle to the live call manager (QA builds only).
class QaHooks {
  static Object? activeManager;
}

class QaLog {
  static void event(String name, [Map<String, Object?> data = const {}]) {
    if (!kQaBuild) return;
    _emit('QA_EVENT', {'t': DateTime.now().millisecondsSinceEpoch, 'ev': name, ...data});
  }

  static void _emit(String prefix, Map<String, Object?> m) {
    // print (not debugPrint) so lines are never throttled or dropped.
    // ignore: avoid_print
    print('$prefix ${jsonEncode(m, toEncodable: (o) => o.toString())}');
  }

  /// Extracts the codec/fmtp lines that matter for quality analysis.
  static Map<String, Object?> sdpSummary(String? sdp) {
    if (sdp == null) return const {};
    final lines = sdp.split(RegExp(r'\r?\n'));
    return {
      'm': lines.where((l) => l.startsWith('m=')).toList(),
      'opusFmtp': lines.where((l) => l.startsWith('a=fmtp:') && l.contains('useinbandfec')).toList(),
      'videoRtpmap': lines
          .where((l) => l.startsWith('a=rtpmap:') && RegExp(r'(VP8|VP9|H264|AV1)').hasMatch(l))
          .toList(),
    };
  }
}

/// Polls getStats() every second during a connected call and prints one JSON
/// line per sample with the reports needed for quality verdicts.
class QaStatsSampler {
  Timer? _timer;
  int _seq = 0;
  static const _types = {
    'outbound-rtp',
    'inbound-rtp',
    'remote-inbound-rtp',
    'candidate-pair',
    'local-candidate',
    'remote-candidate',
    'codec',
    'media-source',
    'track',
    'transport',
  };

  void start(RTCPeerConnection pc, String role) {
    if (!kQaBuild) return;
    stop();
    _timer = Timer.periodic(const Duration(milliseconds: kQaStatsMs), (_) async {
      try {
        final reports = await pc.getStats();
        final out = <Map<String, Object?>>[];
        for (final r in reports) {
          if (_types.contains(r.type)) {
            out.add({'type': r.type, 'id': r.id, ...r.values.map((k, v) => MapEntry(k.toString(), v))});
          }
        }
        QaLog._emit('QA_STATS', {
          't': DateTime.now().millisecondsSinceEpoch,
          'seq': _seq++,
          'role': role,
          'reports': out,
        });
      } catch (e) {
        QaLog.event('stats_error', {'error': '$e'});
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

@visibleForTesting
bool get qaInstrumentationCompiledIn => kQaBuild;
