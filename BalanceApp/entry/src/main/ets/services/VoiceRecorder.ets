/*
 * VoiceRecorder.ets
 *
 * 录音并落成 16 位 PCM 单声道 WAV —— 供语音输入转写（POST /v1/tools/asr）使用。
 * 1. AudioCapturer 参数固定 16 kHz / 单声道 / S16LE / RAW（服务端 WAV 支持 8k~48k，16k 足够）；
 * 2. 打开文件先占 44 字节 WAV 头，录音数据追加写入，停止时回填头部（RIFF/fmt/data）；
 * 3. 上限 120 秒（官方 ASR 时长上限），到点自动停；8 MiB 上限由 16k/16bit/单声道天然满足；
 * 4. 单实例：重复 start 直接返回，stop 幂等；失败路径关闭文件、删除残片。
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

export class VoiceRecorder {
  private static capturer: audio.AudioCapturer | undefined = undefined;
  private static file: fs.File | undefined = undefined;
  private static path: string = '';
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
      const path: string = `${context.cacheDir}/voice_${Date.now()}.wav`;
      const file: fs.File = fs.openSync(path,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      // 先占位 44 字节，停止时回填真实头部（录音数据紧接着写）。
      const placeholder: ArrayBuffer = new ArrayBuffer(WAV_HEADER_SIZE);
      fs.writeSync(file.fd, placeholder);

      VoiceRecorder.capturer = capturer;
      VoiceRecorder.file = file;
      VoiceRecorder.path = path;
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

  /** 停止录音并回填 WAV 头；返回文件路径（'' 表示没有可用录音）。 */
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
    // 等读取循环退出，避免与回填头部/关闭文件竞争。
    if (VoiceRecorder.loop !== undefined) {
      try {
        await VoiceRecorder.loop;
      } catch (_loopErr) {
      }
      VoiceRecorder.loop = undefined;
    }

    const file: fs.File | undefined = VoiceRecorder.file;
    const path: string = VoiceRecorder.path;
    const bytes: number = VoiceRecorder.bytes;
    VoiceRecorder.file = undefined;
    VoiceRecorder.path = '';
    VoiceRecorder.bytes = 0;
    if (file === undefined) {
      return '';
    }
    try {
      const header: ArrayBuffer = VoiceRecorder.buildWavHeader(bytes);
      fs.writeSync(file.fd, header, { offset: 0 });
      fs.closeSync(file);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'finalize failed: %{public}s', String(err));
      try {
        fs.closeSync(file);
      } catch (_closeErr) {
      }
      try {
        fs.unlinkSync(path);
      } catch (_unlinkErr) {
      }
      return '';
    }
    return path;
  }

  /** 放弃本次录音（离开页面等场景）：停录、删文件。 */
  public static async cancel(): Promise<void> {
    const path: string = await VoiceRecorder.stop();
    if (path.length > 0) {
      try {
        fs.unlinkSync(path);
      } catch (_err) {
      }
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
    const path: string = VoiceRecorder.path;
    VoiceRecorder.path = '';
    if (path.length > 0) {
      try {
        fs.unlinkSync(path);
      } catch (_err) {
      }
    }
    VoiceRecorder.bytes = 0;
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
