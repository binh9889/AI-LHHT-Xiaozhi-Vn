import 'dart:typed_data';

/// Gom các chunk PCM có kích thước bất kỳ thành frame cố định mà không làm rơi
/// byte và không tự chèn silence.
class PcmFrameBuffer {
  final int frameBytes;
  final List<int> _carry = <int>[];

  PcmFrameBuffer({required this.frameBytes}) {
    if (frameBytes <= 0) {
      throw ArgumentError.value(frameBytes, 'frameBytes', 'must be > 0');
    }
  }

  int get pendingBytes => _carry.length;

  List<Uint8List> add(Uint8List chunk) {
    if (chunk.isNotEmpty) _carry.addAll(chunk);
    final frames = <Uint8List>[];
    while (_carry.length >= frameBytes) {
      frames.add(Uint8List.fromList(_carry.sublist(0, frameBytes)));
      _carry.removeRange(0, frameBytes);
    }
    return frames;
  }

  void clear() => _carry.clear();
}
