part of 'http2.dart';

class Http2Frame {
  final int length;
  final int type;
  final int flags;
  final int streamId;
  final Uint8List payload;

  Http2Frame({
    required this.length,
    required this.type,
    required this.flags,
    required this.streamId,
    required this.payload,
  });

  static const int headerSize = 9;

  static Http2Frame? tryParse(Uint8List buffer) {
    if (buffer.length < headerSize) return null;

    final length = (buffer[0] << 16) | (buffer[1] << 8) | buffer[2];
    if (buffer.length < headerSize + length) return null;

    final type = buffer[3];
    final flags = buffer[4];
    final streamId = ((buffer[5] & 0x7F) << 24) |
                     (buffer[6] << 16) |
                     (buffer[7] << 8) |
                     (buffer[8]);

    final payload = buffer.sublist(9, 9 + length);

    return Http2Frame(
      length: length,
      type: type,
      flags: flags,
      streamId: streamId,
      payload: Uint8List.fromList(payload),
    );
  }

  static int getTotalFrameSize(Uint8List buffer) {
    if (buffer.length < headerSize) return 0;
    final length = (buffer[0] << 16) | (buffer[1] << 8) | buffer[2];
    return headerSize + length;
  }
}