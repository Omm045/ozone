class SdpUtils {
  /// Munges SDP to prefer VP8 and Baseline/Constrained-Baseline H.264 codecs
  /// in the m=video line. This prevents cross-platform video freezing when
  /// Apple Silicon VideoToolbox hardware encoder (which defaults to H.264 High Profile)
  /// negotiates with Android devices whose MediaCodec decoders often freeze or drop frames.
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

    final vp8Pts = <String>[];
    final baselineH264Pts = <String>[];
    final otherPts = <String>[];

    for (final pt in payloadTypes) {
      final codec = ptToCodec[pt];
      if (codec == 'VP8') {
        vp8Pts.add(pt);
      } else if (codec == 'H264') {
        final fmtp = ptToFmtp[pt] ?? '';
        // Baseline / Constrained-Baseline profile starts with 42 (e.g. 42001f, 42e01f)
        if (fmtp.contains('profile-level-id=42')) {
          baselineH264Pts.add(pt);
        } else {
          otherPts.add(pt);
        }
      } else {
        otherPts.add(pt);
      }
    }

    final reordered = [...vp8Pts, ...baselineH264Pts, ...otherPts];
    lines[mVideoIndex] = '${header.join(' ')} ${reordered.join(' ')}';
    return lines.join(newline);
  }
}
