import 'dart:typed_data';

import 'package:flutter_baji_demo/protocol/baji_frame.dart';
import 'package:flutter_baji_demo/protocol/baji_protocol.dart';
import 'package:flutter_baji_demo/protocol/frame_assembler.dart';
import 'package:flutter_baji_demo/protocol/frame_codec.dart';
import 'package:flutter_test/flutter_test.dart';

BajiFrame frame(int type, int total, int index, String payload) => BajiFrame(
      head: FrameCodec.headToApp,
      type: type,
      totalPackets: total,
      packetIndex: index,
      payload: Uint8List.fromList(payload.codeUnits),
    );

Uint8List payloadOf(String text) => Uint8List.fromList(text.codeUnits);

void main() {
  test('single packet passes through', () {
    final assembler = FrameAssembler(policy: PacketIndexPolicy.ascending);
    expect(
      assembler.offer(frame(7, 0, 0, '{"type":7}')),
      payloadOf('{"type":7}'),
    );
  });

  test('out of order packets are reassembled ascending', () {
    final assembler = FrameAssembler(policy: PacketIndexPolicy.ascending);
    expect(assembler.offer(frame(6, 3, 2, 'BBB')), isNull);
    expect(assembler.offer(frame(6, 3, 3, 'CCC')), isNull);
    expect(assembler.offer(frame(6, 3, 1, 'AAA')), payloadOf('AAABBBCCC'));
  });

  test('countdown packets are reassembled in order', () {
    final assembler = FrameAssembler(policy: PacketIndexPolicy.countdown);
    expect(assembler.offer(frame(6, 3, 1, 'CCC')), isNull);
    expect(assembler.offer(frame(6, 3, 3, 'AAA')), isNull);
    expect(assembler.offer(frame(6, 3, 2, 'BBB')), payloadOf('AAABBBCCC'));
  });

  test('missing packet keeps returning null', () {
    final assembler = FrameAssembler(policy: PacketIndexPolicy.ascending);
    expect(assembler.offer(frame(6, 3, 1, 'AAA')), isNull);
    expect(assembler.offer(frame(6, 3, 3, 'CCC')), isNull);
    expect(assembler.offer(frame(6, 3, 3, 'CCC')), isNull);
  });

  test('interleaved types do not mix', () {
    final assembler = FrameAssembler(policy: PacketIndexPolicy.ascending);
    expect(assembler.offer(frame(4, 2, 1, 'A')), isNull);
    expect(assembler.offer(frame(6, 2, 1, 'X')), isNull);
    expect(assembler.offer(frame(6, 2, 2, 'Y')), payloadOf('XY'));
    expect(assembler.offer(frame(4, 2, 2, 'B')), payloadOf('AB'));
  });

  test('countdown to zero packets are reassembled descending', () {
    final assembler = FrameAssembler(policy: PacketIndexPolicy.countdownToZero);
    expect(assembler.offer(frame(6, 3, 0, 'CCC')), isNull);
    expect(assembler.offer(frame(6, 3, 2, 'AAA')), isNull);
    expect(assembler.offer(frame(6, 3, 1, 'BBB')), payloadOf('AAABBBCCC'));
  });

  test('total change resets session', () {
    final assembler = FrameAssembler(policy: PacketIndexPolicy.ascending);
    expect(assembler.offer(frame(6, 3, 1, 'OLD')), isNull);
    expect(assembler.offer(frame(6, 2, 1, 'NEW1')), isNull);
    expect(assembler.offer(frame(6, 2, 2, 'NEW2')), payloadOf('NEW1NEW2'));
  });

  test('compact frames append in arrival order', () {
    final assembler = FrameAssembler();
    final first = BajiFrame(
      head: FrameCodec.headToApp,
      type: 6,
      totalPackets: 2,
      packetIndex: 0,
      payload: payloadOf('AA'),
      format: FrameFormat.compact5,
    );
    final second = BajiFrame(
      head: FrameCodec.headToApp,
      type: 6,
      totalPackets: 2,
      packetIndex: 0,
      payload: payloadOf('BB'),
      format: FrameFormat.compact5,
    );
    expect(assembler.offer(first), isNull);
    expect(assembler.offer(second), payloadOf('AABB'));
  });
}
