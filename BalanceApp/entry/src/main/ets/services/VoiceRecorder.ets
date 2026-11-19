/*
 * VoiceRecorder.ets
 *
 * 录音并落成 16 位 PCM 单声道 WAV —— 供语音输入转写（POST /v1/tools/asr）使用。
 * 1. AudioCapturer 参数固定 16 kHz / 单声道 / S16LE / RAW（服务端 WAV 支持 8k~48k）；
 * 2. 录音期间先写 .pcm 原始数据，停止时再新建 .wav 写标准 44 字节头并分块拷贝 PCM。
 *    Reason: 早期实现是「先占位 44 字节 + 停止时按 offset 回填头部」，真机实测服务端
 *    返回 400（音频格式不支持）——回填位置不可靠会让文件以 44 个 0 开头。分块拷贝不依赖
 *    seek/offset 语义，结果确定。
 * 3. 上限 120 秒（官方 ASR 时长上限）；16k×2B×120s≈3.8 MB，远低于 8 MiB 限制；
 * 4. 单实例：重复 start 直接返回，stop 幂等；失败路径关闭文件并删除 .pcm/.wav 残片。
 *
 * 严格遵守 ArkTS 规范：无 any/unknown，无解构，捕获异常转为 Error 类型。
 */

import { audio } from '@kit.AudioKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'VoiceRecorder';
const SAMPLING_RATE = 16000;
const CHANNELS = 1;
const BYTES_PER_SAMPLE = 2;
/** 每次读 100ms（16k × 2 字节 × 0.1s）。 */
const READ_SIZE = 3200;
const MAX_SECONDS = 120;
const MAX_BYTES = SAMPLING_RATE * CHANNELS * BYTES_PER_SAMPLE * MAX_SECONDS;
const WAV_HEADER_SIZE = 44;
/** 收尾时 PCM -> WAV 的分块大小。 */
const COPY_CHUNK = 64 * 1024;

export class VoiceRecorder {
  private static capturer: audio.AudioCapturer | undefined = undefined;
  private static file: fs.File | undefined = undefined;
  private static pcmPath: string = '';
  private static wavPath: string = '';
  private static bytes: number = 0;
  private static recording: boolean = false;
  private static loop: Promise<void> | undefined = undefined;

  public static isRecording(): boolean {
    return VoiceRecorder.recording;
  }

  /** 开始录音；成功返回 true（失败已清理，调用方只需提示）。 */
  public static async start(context: common.UIAbilityContext): Promise<boolean> {
    if (VoiceRecorder.recording) {
      return true;
    }
    try {
      const streamInfo: audio.AudioStreamInfo = {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      };
      const capturerInfo: audio.AudioCapturerInfo = {
        source: audio.SourceType.SOURCE_TYPE_MIC,
        capturerFlags: 0
      };
      const options: audio.AudioCapturerOptions = {
        streamInfo: streamInfo,
        capturerInfo: capturerInfo
      };
      const capturer: audio.AudioCapturer = await audio.createAudioCapturer(options);
      const stamp: number = Date.now();
      const pcmPath: string = `${context.cacheDir}/voice_${stamp}.pcm`;
      const wavPath: string = `${context.cacheDir}/voice_${stamp}.wav`;
      const file: fs.File = fs.openSync(pcmPath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);

      VoiceRecorder.capturer = capturer;
      VoiceRecorder.file = file;
      VoiceRecorder.pcmPath = pcmPath;
      VoiceRecorder.wavPath = wavPath;
      VoiceRecorder.bytes = 0;
      VoiceRecorder.recording = true;
      await capturer.start();
      VoiceRecorder.loop = VoiceRecorder.readLoop(capturer);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'start failed: %{public}s', String(err));
      VoiceRecorder.cleanup();
      return false;
    }
  }

  /** 停止录音并封装 WAV；返回文件路径（'' 表示没有可用录音）。 */
  public static async stop(): Promise<string> {
    if (!VoiceRecorder.recording && VoiceRecorder.file === undefined) {
      return '';
    }
    VoiceRecorder.recording = false;
    const capturer: audio.AudioCapturer | undefined = VoiceRecorder.capturer;
    VoiceRecorder.capturer = undefined;
    if (capturer !== undefined) {
      try {
        await capturer.stop();
      } catch (_stopErr) {
      }
      try {
        await capturer.release();
      } catch (_releaseErr) {
      }
    }
    // 等读取循环退出，避免与关闭文件竞争。
    if (VoiceRecorder.loop !== undefined) {
      try {
        await VoiceRecorder.loop;
      } catch (_loopErr) {
      }
      VoiceRecorder.loop = undefined;
    }

    const file: fs.File | undefined = VoiceRecorder.file;
    const pcmPath: string = VoiceRecorder.pcmPath;
    const wavPath: string = VoiceRecorder.wavPath;
    const bytes: number = VoiceRecorder.bytes;
    VoiceRecorder.file = undefined;
    VoiceRecorder.pcmPath = '';
    VoiceRecorder.wavPath = '';
    VoiceRecorder.bytes = 0;
    if (file === undefined) {
      return '';
    }
    try {
      fs.closeSync(file);
    } catch (_closeErr) {
    }
    if (bytes <= 0) {
      VoiceRecorder.removeQuietly(pcmPath);
      return '';
    }
    const ok: boolean = VoiceRecorder.buildWav(pcmPath, wavPath, bytes);
    VoiceRecorder.removeQuietly(pcmPath);
    hilog.info(DOMAIN, TAG, 'recorded %{public}d bytes, wav=%{public}s ok=%{public}s',
      bytes, wavPath, String(ok));
    if (!ok) {
      VoiceRecorder.removeQuietly(wavPath);
      return '';
    }
    return wavPath;
  }

  /** 放弃本次录音（离开页面等场景）：停录并删除临时文件。 */
  public static async cancel(): Promise<void> {
    const path: string = await VoiceRecorder.stop();
    if (path.length > 0) {
      VoiceRecorder.removeQuietly(path);
    }
  }

  private static async readLoop(capturer: audio.AudioCapturer): Promise<void> {
    while (VoiceRecorder.recording) {
      const file: fs.File | undefined = VoiceRecorder.file;
      if (file === undefined) {
        break;
      }
      let buffer: ArrayBuffer;
      try {
        buffer = await capturer.read(READ_SIZE, true);
      } catch (_readErr) {
        break;
      }
      if (!VoiceRecorder.recording) {
        break;
      }
      if (buffer.byteLength === 0) {
        continue;
      }
      try {
        fs.writeSync(file.fd, buffer);
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'write failed: %{public}s', String(err));
        VoiceRecorder.recording = false;
        break;
      }
      VoiceRecorder.bytes += buffer.byteLength;
      if (VoiceRecorder.bytes >= MAX_BYTES) {
        // 到达 120 秒上限：由调用方的定时器负责收尾，这里只停止继续读。
        VoiceRecorder.recording = false;
        break;
      }
    }
  }

  /**
   * 把 .pcm 封装成 .wav：先写 44 字节头，再分块拷贝 PCM。
   * Reason: 不依赖文件的 offset/seek 语义，避免"头部没写到文件开头"导致服务端 400。
   */
  private static buildWav(pcmPath: string, wavPath: string, dataBytes: number): boolean {
    let dst: fs.File | undefined = undefined;
    let src: fs.File | undefined = undefined;
    try {
      dst = fs.openSync(wavPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(dst.fd, VoiceRecorder.buildWavHeader(dataBytes));
      src = fs.openSync(pcmPath, fs.OpenMode.READ_ONLY);
      let remaining: number = dataBytes;
      while (remaining > 0) {
        const buffer: ArrayBuffer = new ArrayBuffer(COPY_CHUNK);
        const readBytes: number = fs.readSync(src.fd, buffer);
        if (readBytes <= 0) {
          break;
        }
        const chunk: ArrayBuffer = readBytes === buffer.byteLength ? buffer : buffer.slice(0, readBytes);
        fs.writeSync(dst.fd, chunk);
        remaining -= readBytes;
      }
      return remaining === 0;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'build wav failed: %{public}s', String(err));
      return false;
    } finally {
      if (src !== undefined) {
        try {
          fs.closeSync(src);
        } catch (_e) {
        }
      }
      if (dst !== undefined) {
        try {
          fs.closeSync(dst);
        } catch (_e) {
        }
      }
    }
  }

  private static cleanup(): void {
    VoiceRecorder.recording = false;
    const capturer: audio.AudioCapturer | undefined = VoiceRecorder.capturer;
    VoiceRecorder.capturer = undefined;
    if (capturer !== undefined) {
      try {
        capturer.release();
      } catch (_err) {
      }
    }
    const file: fs.File | undefined = VoiceRecorder.file;
    VoiceRecorder.file = undefined;
    if (file !== undefined) {
      try {
        fs.closeSync(file);
      } catch (_err) {
      }
    }
    VoiceRecorder.removeQuietly(VoiceRecorder.pcmPath);
    VoiceRecorder.removeQuietly(VoiceRecorder.wavPath);
    VoiceRecorder.pcmPath = '';
    VoiceRecorder.wavPath = '';
    VoiceRecorder.bytes = 0;
  }

  private static removeQuietly(path: string): void {
    if (path.length === 0) {
      return;
    }
    try {
      fs.unlinkSync(path);
    } catch (_err) {
    }
  }

  /** 44 字节标准 WAV 头（PCM / 16bit / 单声道）。 */
  private static buildWavHeader(dataBytes: number): ArrayBuffer {
    const buffer: ArrayBuffer = new ArrayBuffer(WAV_HEADER_SIZE);
    const view: DataView = new DataView(buffer);
    VoiceRecorder.writeAscii(view, 0, 'RIFF');
    view.setUint32(4, 36 + dataBytes, true);
    VoiceRecorder.writeAscii(view, 8, 'WAVE');
    VoiceRecorder.writeAscii(view, 12, 'fmt ');
    view.setUint32(16, 16, true);
    view.setUint16(20, 1, true);
    view.setUint16(22, CHANNELS, true);
    view.setUint32(24, SAMPLING_RATE, true);
    view.setUint32(28, SAMPLING_RATE * CHANNELS * BYTES_PER_SAMPLE, true);
    view.setUint16(32, CHANNELS * BYTES_PER_SAMPLE, true);
    view.setUint16(34, 8 * BYTES_PER_SAMPLE, true);
    VoiceRecorder.writeAscii(view, 36, 'data');
    view.setUint32(40, dataBytes, true);
    return buffer;
  }

  private static writeAscii(view: DataView, offset: number, text: string): void {
    let i: number = 0;
    while (i < text.length) {
      view.setUint8(offset + i, text.charCodeAt(i));
      i += 1;
    }
  }
}
