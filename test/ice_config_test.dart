import 'package:flutter_test/flutter_test.dart';
import 'package:ozone/core/webrtc/ice_config_provider.dart';

void main() {
  group('ICE Server Config Provider Tests', () {
    test('Default configuration contains 5 redundant Google STUN servers and no TURN', () {
      const config = IceServerConfig();
      final rtcConfig = config.toWebRtcConfig();

      expect(rtcConfig['sdpSemantics'], 'unified-plan');
      expect(rtcConfig['continualGatheringPolicy'], 'gather_continually');

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

    test('Extensible with future TURN server entries as pure config change', () {
      const turnEntry = {
        'urls': ['turn:turn.cloudflare.com:3478?transport=udp'],
        'username': 'ozone_user',
        'credential': 'ozone_credential',
      };

      const configWithTurn = IceServerConfig(
        stunUrls: IceServerConfig.defaultStunUrls,
        turnServers: [turnEntry],
      );

      final rtcConfig = configWithTurn.toWebRtcConfig();
      final iceServers = rtcConfig['iceServers'] as List<Map<String, dynamic>>;
      expect(iceServers.length, 2);
      expect(iceServers.last['username'], 'ozone_user');
    });
  });
}
