import 'package:flutter_test/flutter_test.dart';
import 'package:ozone/core/webrtc/ice_config_provider.dart';
import 'package:ozone/core/webrtc/webrtc_call_manager.dart';

void main() {
  group('ICE Server Config Provider Tests (STUN-only Direct P2P)', () {
    test('Default configuration contains 5 redundant Google STUN servers and no TURN', () {
      const config = IceServerConfig();
      final rtcConfig = config.toWebRtcConfig();

      expect(rtcConfig['sdpSemantics'], 'unified-plan');
      expect(rtcConfig['continualGatheringPolicy'], 'gather_continually');
      expect(rtcConfig['iceTransportPolicy'], 'all');

      final iceServers = rtcConfig['iceServers'] as List<Map<String, dynamic>>;
      expect(iceServers.length, 1);

      final stunGroup = iceServers.first;
      final urls = stunGroup['urls'] as List<String>;
      expect(urls.length, 5);
      expect(urls, contains('stun:stun.l.google.com:19302'));
      expect(urls, contains('stun:stun1.l.google.com:19302'));
      expect(urls, contains('stun:stun2.l.google.com:19302'));
      expect(urls, contains('stun:stun3.l.google.com:19302'));
      expect(urls, contains('stun:stun4.l.google.com:19302'));
    });

    test('Extensible with future server entries via pure config without code changes', () {
      const customEntry = {
        'urls': ['stun:custom.stun.provider:3478'],
      };

      const configWithCustom = IceServerConfig(
        stunUrls: IceServerConfig.defaultStunUrls,
        turnServers: [customEntry],
      );

      final rtcConfig = configWithCustom.toWebRtcConfig();
      expect(rtcConfig['iceTransportPolicy'], 'all');
      final iceServers = rtcConfig['iceServers'] as List<Map<String, dynamic>>;
      expect(iceServers.length, 2);
    });

    test('ICE candidate type extraction accurately parses host, srflx, and relay', () {
      const hostCandidate =
          'candidate:1 1 UDP 2130706431 192.168.1.100 50000 typ host generation 0';
      const mDnsHostCandidate =
          'candidate:842164929 1 udp 2113937151 d5f3575c-39fc-43d4-9d5f-6212268155cf.local 50000 typ host generation 0';
      const srflxCandidate =
          'candidate:2 1 UDP 1694498815 203.0.113.50 50000 typ srflx raddr 192.168.1.100 rport 50000 generation 0';
      const relayCandidate =
          'candidate:3 1 UDP 842164929 198.51.100.10 50000 typ relay raddr 203.0.113.50 rport 50000 generation 0';

      expect(WebRtcCallManager.extractCandidateType(hostCandidate), 'host');
      expect(WebRtcCallManager.extractCandidateType(mDnsHostCandidate), 'host');
      expect(WebRtcCallManager.extractCandidateType(srflxCandidate), 'srflx');
      expect(WebRtcCallManager.extractCandidateType(relayCandidate), 'relay');
      expect(WebRtcCallManager.extractCandidateType('invalid candidate string'), 'unknown');
      expect(WebRtcCallManager.extractCandidateType(null), 'unknown');
      expect(WebRtcCallManager.extractCandidateType(''), 'unknown');
    });

    test('DefaultIceConfigProvider builds STUN-only WebRTC config with iceTransportPolicy as all', () async {
      const provider = DefaultIceConfigProvider();

      final rtcConfig = await provider.getIceServers(callId: 'call_123');
      expect(rtcConfig['iceTransportPolicy'], 'all');
      expect(rtcConfig['sdpSemantics'], 'unified-plan');
      expect(rtcConfig['continualGatheringPolicy'], 'gather_continually');

      final iceServers = rtcConfig['iceServers'] as List<Map<String, dynamic>>;
      expect(iceServers.length, 1);
      expect(iceServers.first['urls'], IceServerConfig.defaultStunUrls);
    });

    test('DefaultIceConfigProvider works consistently with or without callId parameter', () async {
      const provider = DefaultIceConfigProvider();

      final rtcConfigNoCallId = await provider.getIceServers();
      final rtcConfigWithCallId = await provider.getIceServers(callId: 'test_call_999');

      expect(rtcConfigNoCallId, equals(rtcConfigWithCallId));
    });
  });
}
