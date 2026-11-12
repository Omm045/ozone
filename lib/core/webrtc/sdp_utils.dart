class SdpUtils {
  /// Munges SDP to optimize video and audio codec negotiation for high-end P2P calls:
  /// 1. Video: Prioritizes High-Profile H.264 (profile-level-id=640032 / 6400 for 1080p/4K
  ///    Apple VideoToolbox and Android MediaCodec hardware encoding), followed by
  ///    Constrained-Baseline H.264 (42e01f / 4200), VP8, and VP9 as fallbacks.
  ///    Appends x-google-min-bitrate=2500;x-google-start-bitrate=6000;x-google-max-bitrate=16000
  ///    to video a=fmtp lines so video starts sharp on frame 1 without ramping slowly.
  /// 2. Audio: Tunes Opus to 64 kbps (crystal clear voice), enables in-band FEC
  ///    for packet loss resilience, and sets mono CBR for bandwidth efficiency.
  static String preferCompatibleVideoCodecs(String sdp) {
    if (sdp.isEmpty) return sdp;

    final newline = sdp.contains('\r\n') ? '\r\n' : '\n';
    final lines = sdp.split(newline);

    final mVideoIndex = lines.indexWhere((l) => l.startsWith('m=video '));
    if (mVideoIndex == -1) return sdp;

    final mVideoLine = lines[mVideoIndex];
    final parts = mVideoLine.split(' ');
    if (parts.length < 4) return sdp;

    final header = parts.sublist(0, 3); // ['m=video', port, proto]
    final payloadTypes = parts.sublist(3);

    final ptToCodec = <String, String>{};
    final ptToFmtp = <String, String>{};

    for (final line in lines) {
      if (line.startsWith('a=rtpmap:')) {
        final spaceIdx = line.indexOf(' ');
        if (spaceIdx != -1) {
          final pt = line.substring(9, spaceIdx);
          final codec = line.substring(spaceIdx + 1).split('/')[0].toUpperCase();
          ptToCodec[pt] = codec;
        }
      } else if (line.startsWith('a=fmtp:')) {
        final spaceIdx = line.indexOf(' ');
        if (spaceIdx != -1) {
          final pt = line.substring(7, spaceIdx);
          final fmtp = line.substring(spaceIdx + 1).toLowerCase();
          ptToFmtp[pt] = fmtp;
        }
      }
    }

    final highH264Pts = <String>[];
    final baselineH264Pts = <String>[];
    final otherH264Pts = <String>[];
    final vp8Pts = <String>[];
    final vp9Pts = <String>[];
    final otherPts = <String>[];

    for (final pt in payloadTypes) {
      final codec = ptToCodec[pt];
      if (codec == 'H264') {
        final fmtp = ptToFmtp[pt] ?? '';
        // High Profile H.264 starts with 6400 (e.g. 640032, 64002a)
        if (fmtp.contains('profile-level-id=6400')) {
          highH264Pts.add(pt);
        } else if (fmtp.contains('profile-level-id=42')) {
          baselineH264Pts.add(pt);
        } else {
          otherH264Pts.add(pt);
        }
      } else if (codec == 'VP8') {
        vp8Pts.add(pt);
      } else if (codec == 'VP9') {
        vp9Pts.add(pt);
      } else {
        otherPts.add(pt);
      }
    }

    final reordered = [
      ...highH264Pts,
      ...baselineH264Pts,
      ...otherH264Pts,
      ...vp8Pts,
      ...vp9Pts,
      ...otherPts,
    ];
    lines[mVideoIndex] = '${header.join(' ')} ${reordered.join(' ')}';

    // Inject Google WebRTC bitrate parameters on video fmtp lines so video starts sharp on frame 1
    const bitrateParams = 'x-google-min-bitrate=2500;x-google-start-bitrate=6000;x-google-max-bitrate=16000';
    final videoPts = [...highH264Pts, ...baselineH264Pts, ...otherH264Pts, ...vp8Pts, ...vp9Pts];

    for (final pt in videoPts) {
      final fmtpPrefix = 'a=fmtp:$pt ';
      final fmtpIdx = lines.indexWhere((l) => l.startsWith(fmtpPrefix));
      if (fmtpIdx != -1) {
        final existing = lines[fmtpIdx];
        if (!existing.contains('x-google-min-bitrate')) {
          lines[fmtpIdx] = '$existing;$bitrateParams';
        }
      } else {
        final rtpmapIdx = lines.indexWhere((l) => l.startsWith('a=rtpmap:$pt '));
        if (rtpmapIdx != -1) {
          lines.insert(rtpmapIdx + 1, '$fmtpPrefix$bitrateParams');
        }
      }
    }

    return lines.join(newline);
  }

  /// Tunes Opus audio parameters in SDP for high-clarity voice communication.
  /// Targets 64 kbps (high-fidelity voice), enables in-band forward error correction (FEC)
  /// to recover from packet loss without retransmission, and sets mono (stereo=0)
  /// to eliminate wasted bandwidth on dual-channel voice.
  static String tuneOpusAudio(String sdp, {int bitrateBps = 64000}) {
    if (sdp.isEmpty) return sdp;

    final newline = sdp.contains('\r\n') ? '\r\n' : '\n';
    final lines = sdp.split(newline);

    String? opusPt;
    for (final line in lines) {
      if (line.startsWith('a=rtpmap:') && line.toLowerCase().contains('opus/48000')) {
        final spaceIdx = line.indexOf(' ');
        if (spaceIdx != -1) {
          opusPt = line.substring(9, spaceIdx);
          break;
        }
      }
    }

    if (opusPt == null) return sdp;

    // Prioritize Opus payload type at the very front of the m=audio media descriptor
    final mAudioIndex = lines.indexWhere((l) => l.startsWith('m=audio '));
    if (mAudioIndex != -1) {
      final parts = lines[mAudioIndex].split(' ');
      if (parts.length > 3) {
        final header = parts.sublist(0, 3);
        final pts = parts.sublist(3);
        if (pts.contains(opusPt)) {
          pts.remove(opusPt);
          pts.insert(0, opusPt);
          lines[mAudioIndex] = '${header.join(' ')} ${pts.join(' ')}';
        }
      }
    }

    final fmtpPrefix = 'a=fmtp:$opusPt ';
    final fmtpIndex = lines.indexWhere((l) => l.startsWith(fmtpPrefix));

    const opusParams = 'minptime=10;useinbandfec=1;maxaveragebitrate=64000;stereo=0;sprop-stereo=0;cbr=1';

    if (fmtpIndex != -1) {
      lines[fmtpIndex] = '$fmtpPrefix$opusParams';
    } else {
      // Insert fmtp line right after rtpmap
      final rtpmapIndex = lines.indexWhere((l) => l.startsWith('a=rtpmap:$opusPt '));
      if (rtpmapIndex != -1) {
        lines.insert(rtpmapIndex + 1, '$fmtpPrefix$opusParams');
      }
    }

    return lines.join(newline);
  }

  /// Complete SDP optimization for video and audio.
  static String optimizeSdp(String sdp) {
    var result = preferCompatibleVideoCodecs(sdp);
    result = tuneOpusAudio(result);
    return result;
  }
}
