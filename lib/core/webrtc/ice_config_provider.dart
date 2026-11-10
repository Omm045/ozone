/// ICE Server Configuration Provider (v1: STUN-only)
///
/// Calls rely on STUN + direct peer-to-peer connectivity.
/// Redundant Google STUN servers are configured in a centralized array.
///
/// EXTENSION POINT FOR TURN:
/// To add TURN relay later (e.g. Cloudflare Calls, Twilio, Coturn),
/// add your TURN configuration map to `turnServers` in `IceServerConfig`.
/// No call-setup logic elsewhere needs to change.
class IceServerConfig {
  static const List<String> defaultStunUrls = [
    'stun:stun.l.google.com:19302',
    'stun:stun1.l.google.com:19302',
    'stun:stun2.l.google.com:19302',
    'stun:stun3.l.google.com:19302',
    'stun:stun4.l.google.com:19302',
  ];

  final List<String> stunUrls;
  final List<Map<String, dynamic>> turnServers;

  const IceServerConfig({
    this.stunUrls = defaultStunUrls,
    this.turnServers = const [],
  });

  Map<String, dynamic> toWebRtcConfig() {
    final List<Map<String, dynamic>> iceServers = [];

    // 1. Add STUN servers
    if (stunUrls.isNotEmpty) {
      iceServers.add({'urls': stunUrls});
    }

    // 2. Add TURN servers (when configured in future)
    iceServers.addAll(turnServers);

    return {
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      'continualGatheringPolicy': 'gather_continually',
    };
  }
}

abstract class IceConfigProvider {
  Map<String, dynamic> getIceServers();
}

class DefaultIceConfigProvider implements IceConfigProvider {
  final IceServerConfig config;

  const DefaultIceConfigProvider({this.config = const IceServerConfig()});

  @override
  Map<String, dynamic> getIceServers() {
    return config.toWebRtcConfig();
  }
}
