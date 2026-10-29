import 'dart:async';
import 'dart:typed_data';

import '../core/baji_log.dart';
import '../protocol/baji_protocol.dart';
import '../protocol/command_codec.dart';
import '../protocol/frame_codec.dart';
import 'jpg_bin_encoder.dart';
import 'transfer_models.dart';

typedef FrameSender = Future<void> Function({
  required int type,
  required Uint8List payload,
  required int totalPackets,
  required int packetIndex,
  required int frameNumber,
  String? logLabel,
});

class TransferCancelled implements Exception {
  const TransferCancelled();
}

/// 文件传输状态机，按协议节奏逐帧发送。
class BajiTransferManager {
  BajiTransferManager({required this.sender, this.failureProbe});

  final FrameSender sender;

  /// 每帧发送前询问「设备是否已报错」，返回原因则终止传输。
  final String? Function()? failureProbe;

  Future<TransferResult> transfer({
    required TransferKind kind,
    required List<TransferFile> files,
    TransferOptions options = const TransferOptions(),
    void Function(TransferProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (files.isEmpty) return const TransferFailure('未选择文件');
    if (isCancelled?.call() == true) throw const TransferCancelled();

    final encoding = BajiConfig.dataEncoding;
    final chunkSize = BajiConfig.rawChunkSize(encoding: encoding);
    final prepared = switch (kind) {
      TransferKind.watchFace => files.take(options.watchFaceNames.length).toList(),
      TransferKind.album => files.map((file) {
          if (file.binWrapped) {
            BajiLog.instance.transfer(
              '传输',
              '相册 bin ${file.name}：已是 IMB 容器 ${file.bytes.length}B，跳过封装',
            );
            return file;
          }
          final bin = JpgBinEncoder.encode(
            file.bytes,
            width: file.width,
            height: file.height,
          );
          BajiLog.instance.transfer(
            '传输',
            '相册图片 ${file.name}：JPG ${file.bytes.length}B -> '
                'IMB bin ${bin.length}B（${bin.length - file.bytes.length}B 头）',
          );
          return file.copyWith(bytes: bin);
        }).toList(),
      _ => files,
    };

    final totalBytes = prepared.fold<int>(0, (sum, file) => sum + file.bytes.length);
    final startedAt = DateTime.now();
    var sentBytes = 0;

    Future<void> sendFile(int type, TransferFile file, int fileIndex) async {
      if (file.bytes.isEmpty) {
        throw StateError('文件 ${file.name} 为空');
      }
      final usesRawEnvelope = kind == TransferKind.album ||
          kind == TransferKind.ambience ||
          kind == TransferKind.marquee ||
          kind == TransferKind.slideshow;
      final rawPayloads = usesRawEnvelope
          ? CommandCodec.rawFileEnvelopeChunks(
              type,
              file.bytes,
              maxChunk: BajiConfig.maxDataPayload(),
            )
          : null;
      final totalChunks = rawPayloads?.length ??
          (file.bytes.length + chunkSize - 1) ~/ chunkSize;
      final logChunkSize = usesRawEnvelope ? BajiConfig.maxDataPayload() : chunkSize;

      if (usesRawEnvelope) {
        BajiLog.instance.transfer(
          '传输',
          'App->设备 type=0x${type.toRadixString(16).padLeft(2, '0').toUpperCase()} '
              '${file.name}：总大小 ${file.bytes.length}B，$totalChunks 帧，'
              '分片 ≤$logChunkSize B，编码=JSON头+RAW（整包 bin 切片），'
              '帧头=${BajiConfig.frameFormat.name}，包号=${BajiConfig.packetIndexPolicy.name}',
        );
      } else {
        BajiLog.instance.transfer(
          '传输',
          'App->设备 type=0x${type.toRadixString(16).padLeft(2, '0').toUpperCase()} '
              '${file.name}：总大小 ${file.bytes.length}B，$totalChunks 帧，'
              '分片 $logChunkSize B，编码=${encoding.name}，'
              '帧头=${BajiConfig.frameFormat.name}，包号=${BajiConfig.packetIndexPolicy.name}',
        );
      }

      final rawPerChunk = usesRawEnvelope ? file.bytes.length ~/ totalChunks : 0;
      var chunks = 0;
      var sentFileBytes = 0;

      while (chunks < totalChunks) {
        if (isCancelled?.call() == true) throw const TransferCancelled();
        final deviceFailure = failureProbe?.call();
        if (deviceFailure != null) throw StateError(deviceFailure);
        final payload = rawPayloads != null
            ? rawPayloads[chunks]
            : CommandCodec.fileChunk(
                type,
                Uint8List.sublistView(
                  file.bytes,
                  chunks * chunkSize,
                  (chunks + 1) * chunkSize < file.bytes.length
                      ? (chunks + 1) * chunkSize
                      : file.bytes.length,
                ),
                encoding: encoding,
              );
        final rawBytes = usesRawEnvelope
            ? (chunks == totalChunks - 1
                ? file.bytes.length - sentFileBytes
                : rawPerChunk)
            : ((chunkSize < file.bytes.length - chunks * chunkSize)
                ? chunkSize
                : file.bytes.length - chunks * chunkSize);

        final isSingle = totalChunks <= 1;
        final isLast = chunks == totalChunks - 1;
        final protocolTotal = isSingle ? 0 : totalChunks;
        final label = isSingle
            ? '单帧'
            : chunks == 0
                ? '首帧'
                : isLast
                    ? '末帧'
                    : null;

        var attempt = 0;
        while (true) {
          if (isCancelled?.call() == true) throw const TransferCancelled();
          try {
            final packetIndex = isSingle
                ? 0
                : FrameCodec.packetIndexFor(
                    BajiConfig.packetIndexPolicy,
                    chunks,
                    totalChunks,
                  );
            await sender(
              type: type,
              payload: payload,
              totalPackets: protocolTotal,
              packetIndex: packetIndex,
              frameNumber: chunks + 1,
              logLabel: label,
            );
            break;
          } catch (error) {
            if (error is TransferCancelled) rethrow;
            attempt++;
            if (attempt > BajiConfig.chunkWriteRetries) {
              throw StateError(
                '文件 ${file.name} 第 ${chunks + 1}/$totalChunks 帧写入失败：$error',
              );
            }
            BajiLog.instance.transferWarn(
              '传输',
              '分片重试 $attempt/${BajiConfig.chunkWriteRetries}：$error',
            );
            await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
          }
        }

        sentFileBytes += rawBytes;
        sentBytes += rawBytes;
        chunks++;
        if (chunks % 64 == 0) {
          BajiLog.instance.transferTrace(
            '传输',
            '${file.name} 已发送 $sentFileBytes/${file.bytes.length} 字节',
          );
        }
        final elapsedMs =
            DateTime.now().difference(startedAt).inMilliseconds.clamp(1, 1 << 62);
        onProgress?.call(
          TransferProgress(
            kind: kind,
            fileIndex: fileIndex,
            fileCount: prepared.length,
            fileName: file.name,
            sentBytes: sentBytes,
            totalBytes: totalBytes,
            bytesPerSecond: sentBytes * 1000 ~/ elapsedMs,
          ),
        );
        await Future<void>.delayed(BajiConfig.interChunkDelay);
      }
      BajiLog.instance.transfer(
        '传输',
        '文件 ${file.name} 发送完成：$chunks 帧，${file.bytes.length}B',
      );
    }

    try {
      switch (kind) {
        case TransferKind.watchFace:
          for (var index = 0; index < prepared.length; index++) {
            final file = prepared[index];
            final slotName = index < options.watchFaceNames.length
                ? options.watchFaceNames[index]
                : file.name;
            final meta = CommandCodec.watchFaceFile(slotName);
            BajiLog.instance.transfer(
              '传输',
              'App->设备 type=0x${kind.type.toRadixString(16).padLeft(2, '0')} '
                  '元数据: ${String.fromCharCodes(meta)}',
            );
            await sender(
              type: kind.type,
              payload: meta,
              totalPackets: 0,
              packetIndex: 0,
              frameNumber: 1,
              logLabel: '元数据',
            );
            await sendFile(kind.type, file, index);
            if (index < prepared.length - 1) {
              await Future<void>.delayed(options.watchFaceInterval);
            }
          }
        case TransferKind.album:
          final meta = CommandCodec.albumCount(prepared.length);
          BajiLog.instance.transfer(
            '传输',
            'App->设备 type=0x${kind.type.toRadixString(16).padLeft(2, '0')} '
                '元数据: ${String.fromCharCodes(meta)}',
          );
          await sender(
            type: kind.type,
            payload: meta,
            totalPackets: 0,
            packetIndex: 0,
            frameNumber: 1,
            logLabel: '元数据',
          );
          for (var index = 0; index < prepared.length; index++) {
            BajiLog.instance.transfer(
              '传输',
              '相册第 ${index + 1}/${prepared.length} 张，'
                  '等待 ${options.albumInterval.inMilliseconds}ms 后发送',
            );
            await Future<void>.delayed(options.albumInterval);
            if (isCancelled?.call() == true) throw const TransferCancelled();
            await sendFile(kind.type, prepared[index], index);
          }
        case TransferKind.ambience:
        case TransferKind.marquee:
        case TransferKind.slideshow:
          final meta = CommandCodec.ambienceInfo(prepared.length);
          BajiLog.instance.transfer(
            '传输',
            'App->设备 type=0x${kind.type.toRadixString(16).padLeft(2, '0')} '
                '元数据: ${String.fromCharCodes(meta)}',
          );
          await sender(
            type: kind.type,
            payload: meta,
            totalPackets: 0,
            packetIndex: 0,
            frameNumber: 1,
            logLabel: '元数据',
          );
          BajiLog.instance.transfer(
            '传输',
            '${kind.title}等待 ${options.albumInterval.inMilliseconds}ms 后发送',
          );
          await Future<void>.delayed(options.albumInterval);
          if (isCancelled?.call() == true) throw const TransferCancelled();
          await sendFile(kind.type, prepared.first, 0);
        default:
          await sendFile(kind.type, prepared.first, 0);
      }
    } on TransferCancelled {
      rethrow;
    } catch (error) {
      BajiLog.instance.transferError('传输', '传输失败：$error');
      return TransferFailure(error.toString());
    }

    BajiLog.instance.transfer(
      '传输',
      '${kind.title} 传输完成：${prepared.length} 个文件，共 $totalBytes 字节',
    );
    return const TransferSuccess();
  }
}
