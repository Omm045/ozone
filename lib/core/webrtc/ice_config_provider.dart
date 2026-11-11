/// ICE Server Configuration Provider (STUN-only Direct P2P)
///
/// Calls rely on direct STUN peer-to-peer connectivity across local network
/// and public internet routes using 5 redundant Google STUN endpoints.
/// WebRTC gathers host (local network) and srflx (STUN public IP) candidates
/// with iceTransportPolicy: 'all'.
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

    // 2. Add additional servers if provided via config
    if (turnServers.isNotEmpty) {
      iceServers.addAll(turnServers);
    }

    return {
      'iceServers': iceServers,
      'iceTransportPolicy': 'all',
      'sdpSemantics': 'unified-plan',
      'continualGatheringPolicy': 'gather_continually',
    };
  }
}

abstract class IceConfigProvider {
  Future<Map<String, dynamic>> getIceServers({String? callId});
}

class DefaultIceConfigProvider implements IceConfigProvider {
  final IceServerConfig config;

  const DefaultIceConfigProvider({
    this.config = const IceServerConfig(),
  });

  @override
  Future<Map<String, dynamic>> getIceServers({String? callId}) async {
    // Builds ICE configuration with 5 redundant STUN endpoints; no external network call
    return config.toWebRtcConfig();
  }
}
