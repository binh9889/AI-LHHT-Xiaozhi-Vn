import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/utils/pcm_frame_buffer.dart';

void main() {
  test('PCM chunks are re-framed without loss', () {
    final buffer = PcmFrameBuffer(frameBytes: 8);
    final original = Uint8List.fromList(List<int>.generate(21, (i) => i));

    final frames = <Uint8List>[];
    frames.addAll(buffer.add(Uint8List.fromList(original.sublist(0, 3))));
    frames.addAll(buffer.add(Uint8List.fromList(original.sublist(3, 13))));
    frames.addAll(buffer.add(Uint8List.fromList(original.sublist(13))));

    expect(frames.length, 2);
    expect(frames[0], Uint8List.fromList(original.sublist(0, 8)));
    expect(frames[1], Uint8List.fromList(original.sublist(8, 16)));
    expect(buffer.pendingBytes, 5);
  });

  test('oversized chunk yields every complete frame', () {
    final buffer = PcmFrameBuffer(frameBytes: 4);
    final frames = buffer.add(Uint8List.fromList([1,2,3,4,5,6,7,8,9]));
    expect(frames, hasLength(2));
    expect(frames[0], Uint8List.fromList([1,2,3,4]));
    expect(frames[1], Uint8List.fromList([5,6,7,8]));
    expect(buffer.pendingBytes, 1);
  });
}
