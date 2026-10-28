import media from '@ohos.multimedia.media';
import image from '@ohos.multimedia.image';
import fileIo from '@ohos.file.fs';
import { BusinessError } from '@ohos.base';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';

const CHANNEL = 'baji/video';
const JPEG_QUALITY = 90;

/** 保持宽高比的解码目标尺寸（对应 Android 侧 decodeTarget）。 */
class PixelTarget {
  width: number = 0;
  height: number = 0;
}

class SourceSize {
  width: number = 0;
  height: number = 0;
}

/// ohos 的 AVImageGenerator 只支持按关键帧取帧（无 Android OPTION_CLOSEST 的
/// 逐帧精确模式），interval 小于 GOP 时相邻帧会重复，属平台能力差异。
class VideoSource {
  private fd: number = -1;
  private generator: media.AVImageGenerator | null = null;
  private extractor: media.AVMetadataExtractor | null = null;
  private packer: image.ImagePacker = image.createImagePacker();

  async open(path: string): Promise<void> {
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    this.fd = file.fd;
    this.generator = await media.createAVImageGenerator();
    this.generator.fdSrc = { fd: this.fd };
    this.extractor = await media.createAVMetadataExtractor();
    this.extractor.fdSrc = { fd: this.fd };
  }

  async close(): Promise<void> {
    try {
      await this.generator?.release();
    } catch (err) {
      // 释放失败不影响主流程
    }
    try {
      await this.extractor?.release();
    } catch (err) {
      // 同上
    }
    if (this.fd >= 0) {
      try {
        fileIo.closeSync(this.fd);
      } catch (err) {
        // 同上
      }
      this.fd = -1;
    }
    this.generator = null;
    this.extractor = null;
  }

  /** 容器时长，毫秒；元数据缺失时返回 0（与 Android 行为一致）。 */
  async durationMs(): Promise<number> {
    const extractor = this.extractor;
    if (extractor == null) {
      return 0;
    }
    const metadata = await extractor.fetchMetadata();
    const value = Number(metadata[media.MediaDescriptionKey.MD_KEY_DURATION]);
    return Number.isFinite(value) ? value : 0;
  }

  async fetchFrame(timeUs: number, target: PixelTarget | null): Promise<image.PixelMap | null> {
    const generator = this.generator;
    if (generator == null) {
      return null;
    }
    const params: media.PixelMapParams = {};
    if (target != null) {
      params.width = target.width;
      params.height = target.height;
    }
    try {
      return await generator.fetchFrameByTime(
        timeUs,
        media.AVImageQueryOptions.AV_IMAGE_QUERY_CLOSEST_SYNC,
        params
      );
    } catch (err) {
      return null;
    }
  }

  /** 压缩为 JPEG 字节流。 */
  async packJpeg(pixelMap: image.PixelMap): Promise<Uint8Array> {
    const options: image.PackingOption = { format: 'image/jpeg', quality: JPEG_QUALITY };
    const buffer = await this.packer.packing(pixelMap, options);
    return new Uint8Array(buffer);
  }
}

function decodeTarget(width: number, height: number, size: number, cover: boolean): PixelTarget | null {
  if (width <= 0 || height <= 0 || size <= 0) {
    return null;
  }
  const longSide = Math.max(width, height);
  const shortSide = Math.min(width, height);
  const target = new PixelTarget();
  if (cover) {
    // 短边压到 size，抽帧后还要居中裁方
    if (shortSide <= size) {
      return null;
    }
    const longTarget = Math.ceil(size * longSide / shortSide);
    if (width >= height) {
      target.width = longTarget;
      target.height = size;
    } else {
      target.width = size;
      target.height = longTarget;
    }
    return target;
  }
  // 长边压到 size（预览）
  if (longSide <= size) {
    return null;
  }
  const scale = size / longSide;
  target.width = Math.max(1, Math.round(width * scale));
  target.height = Math.max(1, Math.round(height * scale));
  return target;
}

class BajiVideoHandler implements MethodCallHandler {
  private intArg(call: MethodCall, key: string, fallback: number): number {
    const raw = call.argument(key) as number | undefined;
    return typeof raw === 'number' && Number.isFinite(raw) ? raw : fallback;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    const path = call.argument('path') as string;
    if (path == null || path.length === 0) {
      result.error('bad_args', 'path is required', null);
      return;
    }
    if (call.method === 'load') {
      this.runLoad(result, path, this.intArg(call, 'maxSize', 720));
    } else if (call.method === 'extract') {
      this.runExtract(
        result,
        path,
        this.intArg(call, 'intervalMs', 100),
        this.intArg(call, 'maxFrames', 30),
        this.intArg(call, 'maxDurationMs', 3000),
        this.intArg(call, 'size', 368)
      );
    } else {
      result.notImplemented();
    }
  }

  /** 返回 {durationMs, preview}；preview 为长边不超过 maxSize 的 JPEG 预览。 */
  private async runLoad(result: MethodResult, path: string, maxSize: number): Promise<void> {
    const source = new VideoSource();
    try {
      await source.open(path);
      const durationMs = await source.durationMs();
      const first = await source.fetchFrame(0, null);
      if (first == null) {
        result.error('video_error', '无法解码视频帧', null);
        return;
      }
      const info = await first.getImageInfo();
      const target = decodeTarget(info.size.width, info.size.height, maxSize, false);
      let frame = first;
      if (target != null) {
        const scaled = await source.fetchFrame(0, target);
        if (scaled != null) {
          await first.release();
          frame = scaled;
        } else {
          // 缩放取帧失败时手动缩放兜底
          await frame.scale(target.width / info.size.width, target.height / info.size.height);
        }
      }
      const preview = await source.packJpeg(frame);
      await frame.release();
      const response: Map<string, Object> = new Map<string, Object>();
      response.set('durationMs', durationMs);
      if (preview != null) {
        response.set('preview', preview);
      }
      result.success(response);
    } catch (err) {
      const businessError = err as BusinessError;
      result.error('video_error', businessError.message ?? '读取视频信息失败', null);
    } finally {
      await source.close();
    }
  }

  /** 按 intervalMs 均匀抽帧，输出 size×size 居中裁方 JPEG 序列。 */
  private async runExtract(
    result: MethodResult,
    path: string,
    intervalMs: number,
    maxFrames: number,
    maxDurationMs: number,
    size: number
  ): Promise<void> {
    const source = new VideoSource();
    try {
      await source.open(path);
      const durationMs = await source.durationMs();
      const effective = Math.min(durationMs, maxDurationMs);
      let count = 1;
      if (effective > 0 && intervalMs > 0) {
        count = Math.min(maxFrames, Math.max(1, Math.floor(effective / intervalMs)));
      }
      // 先解一帧原始尺寸，用于确定降采样目标
      const first = await source.fetchFrame(0, null);
      let dims: SourceSize | null = null;
      if (first != null) {
        const info = await first.getImageInfo();
        dims = { width: info.size.width, height: info.size.height } as SourceSize;
        await first.release();
      }
      const target = dims != null ? decodeTarget(dims.width, dims.height, size, true) : null;

      const frames: Array<Uint8Array> = new Array<Uint8Array>();
      for (let index = 0; index < count; index++) {
        const timeUs = index * intervalMs * 1000;
        const frame = await source.fetchFrame(timeUs, target);
        if (frame == null) {
          continue;
        }
        const jpeg = await this.squareJpeg(frame, size);
        await frame.release();
        if (jpeg != null) {
          frames.push(jpeg);
        }
      }
      result.success(frames);
    } catch (err) {
      const businessError = err as BusinessError;
      result.error('video_error', businessError.message ?? '视频抽帧失败', null);
    } finally {
      await source.close();
    }
  }

  /** 居中裁方并缩放到 size×size 后压缩（对应 Android squareJpeg）。 */
  private async squareJpeg(frame: image.PixelMap, size: number): Promise<Uint8Array | null> {
    const info = await frame.getImageInfo();
    const side = Math.min(info.size.width, info.size.height);
    if (side <= 0) {
      return null;
    }
    const left = Math.floor((info.size.width - side) / 2);
    const top = Math.floor((info.size.height - side) / 2);
    const region: image.Region = { x: left, y: top, size: { width: side, height: side } };
    await frame.crop(region);
    if (side !== size) {
      const ratio = size / side;
      await frame.scale(ratio, ratio);
    }
    const packer = image.createImagePacker();
    try {
      const options: image.PackingOption = { format: 'image/jpeg', quality: JPEG_QUALITY };
      const buffer = await packer.packing(frame, options);
      return new Uint8Array(buffer);
    } finally {
      try {
        await packer.release();
      } catch (err) {
        // 释放失败不影响返回
      }
    }
  }
}

/** baji/video 通道：视频元信息与抽帧，语义对齐 Android MediaMetadataRetriever 实现。 */
export class BajiVideoChannel {
  private channel: MethodChannel | null = null;

  attach(messenger: BinaryMessenger): void {
    this.channel = new MethodChannel(messenger, CHANNEL);
    this.channel.setMethodCallHandler(new BajiVideoHandler());
  }

  detach(): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }
}
