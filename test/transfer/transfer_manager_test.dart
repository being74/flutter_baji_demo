import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_baji_demo/protocol/baji_protocol.dart';
import 'package:flutter_baji_demo/transfer/baji_transfer_manager.dart';
import 'package:flutter_baji_demo/transfer/transfer_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _SentFrame {
  _SentFrame({
    required this.type,
    required this.payload,
    required this.totalPackets,
    required this.packetIndex,
    required this.frameNumber,
    required this.logLabel,
  });

  final int type;
  final Uint8List payload;
  final int totalPackets;
  final int packetIndex;
  final int frameNumber;
  final String? logLabel;
}

Uint8List concat(List<Uint8List> chunks) {
  final size = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
  final out = Uint8List(size);
  var offset = 0;
  for (final chunk in chunks) {
    out.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  return out;
}

void main() {
  final savedDelay = BajiConfig.interChunkDelay;
  final savedRetries = BajiConfig.chunkWriteRetries;

  setUp(() {
    BajiConfig.interChunkDelay = Duration.zero;
    BajiConfig.chunkWriteRetries = 3;
  });

  tearDown(() {
    BajiConfig.interChunkDelay = savedDelay;
    BajiConfig.chunkWriteRetries = savedRetries;
  });

  test('album sends metadata then one raw envelope split into frames', () async {
    final sent = <_SentFrame>[];
    final manager = BajiTransferManager(
      sender: ({
        required type,
        required payload,
        required totalPackets,
        required packetIndex,
        required frameNumber,
        logLabel,
      }) async {
        sent.add(_SentFrame(
          type: type,
          payload: payload,
          totalPackets: totalPackets,
          packetIndex: packetIndex,
          frameNumber: frameNumber,
          logLabel: logLabel,
        ));
      },
    );

    final jpeg = Uint8List(700)..setRange(698, 700, [0xFF, 0xD9]);
    final progress = <TransferProgress>[];
    final result = await manager.transfer(
      kind: TransferKind.album,
      files: [TransferFile(name: 'a.jpg', bytes: jpeg, width: 10, height: 10)],
      options: const TransferOptions(
        albumInterval: Duration.zero,
      ),
      onProgress: progress.add,
    );

    expect(result, isA<TransferSuccess>());
    expect(sent.first.logLabel, '元数据');
    expect(utf8.decode(sent.first.payload), '{"type":6,"number":1}');

    final dataFrames = sent.sublist(1);
    expect(dataFrames.length, greaterThan(1));
    expect(dataFrames.first.totalPackets, dataFrames.length);
    expect(dataFrames.first.packetIndex, dataFrames.length - 1);
    expect(dataFrames.last.packetIndex, 0);
    final envelope = concat(dataFrames.map((frame) => frame.payload).toList());
    const prefix = '{"type":6,"data":';
    expect(
      utf8.decode(envelope.sublist(0, prefix.length)),
      prefix,
    );
    expect(envelope.last, 0x7D);
    final bin = envelope.sublist(prefix.length, envelope.length - 1);
    expect(bin.length, 36 + jpeg.length);
    expect(utf8.decode(bin.sublist(0, 3)), 'IMB');
    expect(progress, isNotEmpty);
    expect(progress.last.sentBytes, bin.length);
    expect(progress.last.totalBytes, bin.length);
  });

  test('watch face sends filename metadata before file chunks', () async {
    final sent = <_SentFrame>[];
    final manager = BajiTransferManager(
      sender: ({
        required type,
        required payload,
        required totalPackets,
        required packetIndex,
        required frameNumber,
        logLabel,
      }) async {
        sent.add(_SentFrame(
          type: type,
          payload: payload,
          totalPackets: totalPackets,
          packetIndex: packetIndex,
          frameNumber: frameNumber,
          logLabel: logLabel,
        ));
      },
    );

    final result = await manager.transfer(
      kind: TransferKind.watchFace,
      files: [
        TransferFile(name: 'bg.bin', bytes: Uint8List(40)),
      ],
      options: const TransferOptions(watchFaceInterval: Duration.zero),
    );

    expect(result, isA<TransferSuccess>());
    expect(utf8.decode(sent.first.payload), '{"type":4,"filename":"bg.bin"}');
    expect(sent.first.logLabel, '元数据');
    expect(sent[1].type, BajiCommands.watchFace);
    expect(sent[1].totalPackets, 0);
    expect(utf8.decode(sent[1].payload).startsWith('{"type":4,"data":['), isTrue);
  });

  test('ambience sends info then a single raw bin', () async {
    final sent = <_SentFrame>[];
    final manager = BajiTransferManager(
      sender: ({
        required type,
        required payload,
        required totalPackets,
        required packetIndex,
        required frameNumber,
        logLabel,
      }) async {
        sent.add(_SentFrame(
          type: type,
          payload: payload,
          totalPackets: totalPackets,
          packetIndex: packetIndex,
          frameNumber: frameNumber,
          logLabel: logLabel,
        ));
      },
    );

    final bin = Uint8List(600)..setRange(598, 600, [0xFF, 0xD9]);
    final result = await manager.transfer(
      kind: TransferKind.ambience,
      files: [TransferFile(name: 'a.gif', bytes: bin, binWrapped: true)],
      options: const TransferOptions(albumInterval: Duration.zero),
    );

    expect(result, isA<TransferSuccess>());
    expect(utf8.decode(sent.first.payload), '{"type":5,"number":1}');
    final dataFrames = sent.sublist(1);
    final envelope = concat(dataFrames.map((frame) => frame.payload).toList());
    const prefix = '{"type":5,"data":';
    expect(utf8.decode(envelope.sublist(0, prefix.length)), prefix);
    expect(envelope.sublist(prefix.length, envelope.length - 1), bin);
  });

  test('retries a failing chunk up to the configured limit', () async {
    var attempts = 0;
    final manager = BajiTransferManager(
      sender: ({
        required type,
        required payload,
        required totalPackets,
        required packetIndex,
        required frameNumber,
        logLabel,
      }) async {
        attempts++;
        if (attempts < 3) throw StateError('write failed');
      },
    );

    final result = await manager.transfer(
      kind: TransferKind.ota,
      files: [TransferFile(name: 'fw', bytes: Uint8List(10))],
    );
    expect(result, isA<TransferSuccess>());
    expect(attempts, 3);
  });

  test('cancellation aborts before sending metadata', () async {
    var calls = 0;
    final manager = BajiTransferManager(
      sender: ({
        required type,
        required payload,
        required totalPackets,
        required packetIndex,
        required frameNumber,
        logLabel,
      }) async {
        calls++;
      },
    );
    await expectLater(
      manager.transfer(
        kind: TransferKind.album,
        files: [TransferFile(name: 'a.jpg', bytes: Uint8List(10))],
        isCancelled: () => true,
      ),
      throwsA(isA<TransferCancelled>()),
    );
    expect(calls, 0);
  });
}
