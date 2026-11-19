/*
 * FileUploadService.ets
 *
 * DeepSeek Files API 文档上传 —— 让模型能读 PDF/Word/PPT/图片等文件。
 * 1. pick：系统文件选择器（DocumentViewPicker），返回文件 URI；
 * 2. upload：先按扩展名选 purpose，再 multipart POST /files；解析完成后才返回 file_id；
 * 3. 约束（官方文档）：purpose 字段必须排在 file 之前；上传 120s + 解析 120s，超时给到 5 分钟；
 *    文档最大 100 MiB（txt/表格/电子书这类 user_data 原文件 32 MiB，且不计费）。
 *
 * 注意：服务端按文件内容判断格式，不依赖 Content-Type，这里统一 octet-stream。
 * 严格遵守 ArkTS 规范：无 any/unknown，无解构，捕获异常转为 Error 类型。
 */

import { http } from '@kit.NetworkKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { cameraPicker, camera } from '@kit.CameraKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'FileUploadService';
const FILES_URL = 'https://api.deepseek.com/files';
const CONNECT_TIMEOUT = 30000;
/** 上传 120s + 解析 120s，留一点余量。 */
const READ_TIMEOUT = 300000;
const MAX_DOC_BYTES = 100 * 1024 * 1024;
const MAX_USER_DATA_BYTES = 32 * 1024 * 1024;

export interface UploadedFile {
  fileId: string;
  fileName: string;
  purpose: string;
  bytes: number;
}

/** 纯文本/表格/电子书：不走解析、不计费，purpose 用 user_data。 */
const USER_DATA_EXTS: string[] = [
  'txt', 'md', 'markdown', 'csv', 'json', 'log', 'xml', 'yaml', 'yml', 'html', 'css',
  'js', 'ts', 'jsx', 'tsx', 'py', 'java', 'kt', 'c', 'cpp', 'h', 'hpp', 'go', 'rs', 'rb',
  'php', 'swift', 'sh', 'sql', 'ini', 'toml', 'xlsx', 'xls', 'epub', 'mobi'
];

/**
 * 图片里能被模型「看见」的格式：必须走 user_data 上传（原文存储），
 * 请求里用 {type:'file', file_id} 参考即可让模型读图。
 * Business Rule: 实测 text_recognition 上传的图片只会被 OCR 成文字（模型只答出图里的数字），
 *   看不到画面；user_data 上传的同一张图能被正确描述。
 */
const VISION_EXTS: string[] = ['png', 'jpg', 'jpeg', 'webp', 'gif'];

/** 其余图片与文档走服务端解析（BMP/TIFF 不支持视觉输入，只能 OCR）。 */
const PARSE_EXTS: string[] = [
  'pdf', 'doc', 'docx', 'ppt', 'pptx', 'bmp', 'tiff', 'tif'
];

export class FileUploadService {
  /** 打开系统文件选择器；用户取消返回 ''。 */
  public static async pick(context: common.UIAbilityContext): Promise<string> {
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const result: string[] = await documentPicker.select(options);
      if (result.length === 0) {
        return '';
      }
      return result[0];
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'picker failed: %{public}s', String(err));
      return '';
    }
  }

  /** 相册选图（系统图库选择器，不需要读媒体权限）；用户取消返回空数组。 */
  public static async pickImages(context: common.UIAbilityContext, maxCount: number): Promise<string[]> {
    try {
      const photoPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = maxCount;
      const result: photoAccessHelper.PhotoSelectResult = await photoPicker.select(options);
      return result.photoUris;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'photo picker failed: %{public}s', String(err));
      return [];
    }
  }

  /** 系统相机拍照；取消返回 ''。 */
  public static async capturePhoto(context: common.UIAbilityContext): Promise<string> {
    try {
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK,
        saveUri: ''
      };
      const result: cameraPicker.PickerResult = await cameraPicker.pick(context,
        [cameraPicker.PickerMediaType.PHOTO], profile);
      return result.resultUri;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'camera picker failed: %{public}s', String(err));
      return '';
    }
  }

  /** 从 URI 取文件名（去查询串、取最后一段）。 */
  public static nameFromUri(uri: string): string {
    let path: string = uri;
    const q: number = path.indexOf('?');
    if (q >= 0) {
      path = path.substring(0, q);
    }
    const slash: number = path.lastIndexOf('/');
    if (slash >= 0) {
      path = path.substring(slash + 1);
    }
    return path.length > 0 ? path : '未命名文件';
  }

  /** 扩展名 -> purpose；不支持的格式返回 ''。 */
  public static purposeFor(fileName: string): string {
    const ext: string = FileUploadService.extensionOf(fileName);
    if (ext.length === 0) {
      return '';
    }
    // 视觉图片优先：user_data 上传后按 file 块引用，模型才能看到画面而不是 OCR 文本。
    if (VISION_EXTS.includes(ext)) {
      return 'user_data';
    }
    if (USER_DATA_EXTS.includes(ext)) {
      return 'user_data';
    }
    if (PARSE_EXTS.includes(ext)) {
      return 'text_recognition';
    }
    return '';
  }

  public static isSupported(fileName: string): boolean {
    return FileUploadService.purposeFor(fileName).length > 0;
  }

  /**
   * 上传并解析；返回服务端 file_id。
   * Business Rule: purpose 必须排在 file 之前（官方明确要求），否则 400。
   *   本地先把 picker URI 复制到应用缓存目录，再用 filePath 走 multipart，
   *   避免直接把 content URI 交给网络库。
   */
  public static async upload(context: common.UIAbilityContext, uri: string, apiKey: string,
    purpose: string): Promise<UploadedFile> {
    if (apiKey.trim().length === 0) {
      throw new Error('未配置 DeepSeek API Key');
    }
    const fileName: string = FileUploadService.nameFromUri(uri);
    const localPath: string = `${context.cacheDir}/upload_${Date.now()}_${FileUploadService.safeName(fileName)}`;
    let localReady: boolean = false;
    const req: http.HttpRequest = http.createHttp();
    try {
      const src: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        fs.copyFileSync(src.fd, localPath);
      } finally {
        fs.closeSync(src);
      }
      localReady = true;

      const stat: fs.Stat = fs.statSync(localPath);
      const limit: number = purpose === 'user_data' ? MAX_USER_DATA_BYTES : MAX_DOC_BYTES;
      if (stat.size > limit) {
        throw new Error(purpose === 'user_data' ? '文件超过 32MB 上限' : '文件超过 100MB 上限');
      }
      if (stat.size === 0) {
        throw new Error('文件为空');
      }

      const form: http.MultiFormData[] = [];
      const purposePart: http.MultiFormData = {
        name: 'purpose',
        contentType: 'text/plain',
        data: purpose
      };
      const filePart: http.MultiFormData = {
        name: 'file',
        contentType: 'application/octet-stream',
        remoteFileName: fileName,
        filePath: localPath
      };
      form.push(purposePart);
      form.push(filePart);

      const resp: http.HttpResponse = await req.request(FILES_URL, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${apiKey.trim()}`,
          'Accept': 'application/json'
        },
        multiFormDataList: form,
        connectTimeout: CONNECT_TIMEOUT,
        readTimeout: READ_TIMEOUT
      });

      if (resp.responseCode !== 200) {
        throw new Error(FileUploadService.errorText(resp.responseCode, resp.result));
      }
      const body: ESObject = typeof resp.result === 'string' ?
        JSON.parse(resp.result as string) as ESObject : resp.result as ESObject;
      const rec: Record<string, ESObject> = body as Record<string, ESObject>;
      const idVal: ESObject = rec['id'];
      if (typeof idVal !== 'string' || (idVal as string).length === 0) {
        throw new Error('上传成功但未返回 file_id');
      }
      const uploaded: UploadedFile = {
        fileId: idVal as string,
        fileName: typeof rec['filename'] === 'string' ? rec['filename'] as string : fileName,
        purpose: typeof rec['purpose'] === 'string' ? rec['purpose'] as string : purpose,
        bytes: typeof rec['bytes'] === 'number' ? rec['bytes'] as number : stat.size
      };
      return uploaded;
    } catch (err) {
      // 失败原因落日志：真机上出现「文件解析失败」时可直接用 hilog 定位（toast 只闪一下）。
      const reason: string = err instanceof Error ? err.message : String(err);
      hilog.error(DOMAIN, TAG, 'upload failed (%{public}s, %{public}s): %{public}s',
        fileName, purpose, reason);
      throw new Error(reason);
    } finally {
      req.destroy();
      if (localReady) {
        try {
          fs.unlinkSync(localPath);
        } catch (_err) {
        }
      }
    }
  }

  private static extensionOf(fileName: string): string {
    const dot: number = fileName.lastIndexOf('.');
    if (dot < 0 || dot === fileName.length - 1) {
      return '';
    }
    return fileName.substring(dot + 1).toLowerCase();
  }

  /** 本地临时文件名安全化：只留字母数字与 ._-，其余替换为 _。 */
  private static safeName(fileName: string): string {
    let out: string = '';
    let i: number = 0;
    while (i < fileName.length) {
      const ch: string = fileName.charAt(i);
      const code: number = fileName.charCodeAt(i);
      const isDigit: boolean = code >= 48 && code <= 57;
      const isUpper: boolean = code >= 65 && code <= 90;
      const isLower: boolean = code >= 97 && code <= 122;
      if (isDigit || isUpper || isLower || ch === '.' || ch === '_' || ch === '-') {
        out += ch;
      } else {
        out += '_';
      }
      i += 1;
    }
    return out.length > 0 ? out : 'file';
  }

  private static errorText(code: number, result: ESObject): string {
    let detail: string = '';
    if (typeof result === 'string') {
      const text: string = result as string;
      detail = text.length > 200 ? text.substring(0, 200) : text;
    }
    if (code === 400) {
      return `文件无法解析或格式不支持${detail.length > 0 ? '：' + detail : ''}`;
    }
    if (code === 408) {
      return '上传超时，请检查网络后重试';
    }
    if (code === 413) {
      return '文件超过大小上限';
    }
    if (code === 429) {
      return '同时上传的文件过多，请稍后重试';
    }
    if (code === 503) {
      return '服务繁忙，请稍后重试';
    }
    if (code === 504) {
      return '文档解析超时，请重试';
    }
    return `上传失败：服务返回 ${code}${detail.length > 0 ? '（' + detail + '）' : ''}`;
  }
}
