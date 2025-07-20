part of 'http2.dart';

enum Http2StreamState {
  idle,
  open,
  halfClosedRemote,
  halfClosedLocal,
  closed,
}

class Http2Stream {
  final int id;
  Http2StreamState state = Http2StreamState.idle;

  // For HEADERS + CONTINUATION merging
  final List<Uint8List> _headerFragments = [];

  // For receiving DATA frame payloads
  final List<Uint8List> _dataFragments = [];

  // Parsed header list (after HPACK decoding)
  List<Header>? decodedHeaders;

  Http2Stream(this.id);

  /// Adds header fragment (from HEADERS or CONTINUATION)
  void addHeaderFragment(Uint8List payload) {
    _headerFragments.add(payload);
  }

  /// Returns full concatenated header block
  Uint8List getFullHeaderBlock() {
    final totalLength = _headerFragments.fold(0, (len, p) => len + p.length);
    final combined = BytesBuilder(copy: false);
    for (final fragment in _headerFragments) {
      combined.add(fragment);
    }
    return combined.toBytes();
  }

  void addDataFragment(Uint8List payload) {
    _dataFragments.add(payload);
  }

  Uint8List getFullBody() {
    final combined = BytesBuilder(copy: false);
    for (final data in _dataFragments) {
      combined.add(data);
    }
    return combined.toBytes();
  }

  void closeRemote() {
    if (state == Http2StreamState.open) {
      state = Http2StreamState.halfClosedRemote;
    } else if (state == Http2StreamState.halfClosedLocal) {
      state = Http2StreamState.closed;
    }
  }

  void closeLocal() {
    if (state == Http2StreamState.open) {
      state = Http2StreamState.halfClosedLocal;
    } else if (state == Http2StreamState.halfClosedRemote) {
      state = Http2StreamState.closed;
    }
  }

  bool get isClosed => state == Http2StreamState.closed;
}