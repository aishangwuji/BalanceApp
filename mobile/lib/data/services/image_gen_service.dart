import 'dart:convert';

import 'package:http/http.dart' as http;

/// 百智云生图（OpenAPI v1）：创建任务 → 轮询任务 → 取结果 URL。
///
/// 约束（与鸿蒙端一致）：
/// 1. 异步任务：create 立即返回 task_id，图片由后台生成，需轮询 `/tasks/{id}`；
/// 2. 结果 URL 会过期（约 1 天），拿到后尽快展示并持久化；
/// 3. 失败语义：HTTP 非 2xx 或 code != ok 抛 [ImageGenException]（带可展示原因）。
class ImageGenService {
  const ImageGenService._();

  static const String _base = 'https://image-generate.app.baizhi.cloud/openapi/v1';
  static const int pollIntervalMs = 4000;
  static const int taskTimeoutMs = 6 * 60 * 1000;
  static const Duration _timeout = Duration(seconds: 30);

  /// 创建一个文生图任务，返回 task_id。
  static Future<String> createTask({
    required String prompt,
    required String ratio,
    required String resolution,
    required int count,
    required String apiKey,
  }) async {
    final Map<String, dynamic> data = await _request(
      'POST',
      '/text_to_image',
      <String, dynamic>{
        'prompt': prompt,
        'image_count': count,
        'ratio': ratio,
        'resolution': resolution,
      },
      apiKey,
    );
    final Object? taskId = data['task_id'];
    if (taskId is! String || taskId.isEmpty) {
      throw const ImageGenException('创建生图任务失败：未返回 task_id');
    }
    return taskId;
  }

  /// 查询任务状态；未完成时 [ImageTaskStatus.imageUrls] 为空。
  static Future<ImageTaskStatus> queryTask(
    String taskId,
    String apiKey,
  ) async {
    final Map<String, dynamic> result =
        await _requestRaw('GET', '/tasks/$taskId', null, apiKey);
    final Object? dataRaw = result['data'];
    final Map<String, dynamic> data =
        dataRaw is Map ? dataRaw.cast<String, dynamic>() : <String, dynamic>{};
    final Object? status = data['status'];
    final Object? code = result['code'];
    final Object? message = result['message'];
    return ImageTaskStatus(
      status: status is String ? status : '',
      imageUrls: _readUrls(data['image_urls']),
      code: code is String ? code : '',
      message: message is String ? message : '',
    );
  }

  static List<String> _readUrls(Object? raw) {
    if (raw is! List) {
      return const <String>[];
    }
    final List<String> out = <String>[];
    for (final Object? item in raw) {
      if (item is String && (item.startsWith('http://') || item.startsWith('https://'))) {
        out.add(item);
      }
    }
    return out;
  }

  static Future<Map<String, dynamic>> _request(
    String method,
    String path,
    Map<String, dynamic>? body,
    String apiKey,
  ) async {
    final Map<String, dynamic> result = await _requestRaw(method, path, body, apiKey);
    final Object? code = result['code'];
    if (code != null && code != 'ok' && code != 0) {
      final Object? message = result['message'];
      throw ImageGenException(
        message is String && message.isNotEmpty ? message : '生图服务返回失败（code=$code）',
      );
    }
    final Object? data = result['data'];
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> _requestRaw(
    String method,
    String path,
    Map<String, dynamic>? body,
    String apiKey,
  ) async {
    final String key = apiKey.trim();
    if (key.isEmpty) {
      throw const ImageGenException('未配置百智云生图 Key（设置 > 工具）');
    }
    try {
      final Uri uri = Uri.parse('$_base$path');
      final Map<String, String> headers = <String, String>{
        'Authorization': 'Bearer $key',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
      };
      final http.Response resp = method == 'GET'
          ? await http.get(uri, headers: headers).timeout(_timeout)
          : await http
              .post(uri, headers: headers, body: jsonEncode(body ?? <String, dynamic>{}))
              .timeout(_timeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw ImageGenException('生图服务返回状态码 ${resp.statusCode}');
      }
      final Object? decoded = jsonDecode(resp.body);
      if (decoded is! Map) {
        throw const ImageGenException('生图服务返回格式异常');
      }
      return decoded.cast<String, dynamic>();
    } on ImageGenException {
      rethrow;
    } catch (error) {
      throw ImageGenException('生图请求失败：$error');
    }
  }
}

class ImageTaskStatus {
  const ImageTaskStatus({
    required this.status,
    required this.imageUrls,
    required this.code,
    required this.message,
  });

  final String status;
  final List<String> imageUrls;
  final String code;
  final String message;

  bool get isDone =>
      status == 'succeeded' || status == 'success' || status == 'completed';

  bool get isFailed => status == 'failed' || status == 'error';
}

class ImageGenException implements Exception {
  const ImageGenException(this.message);

  final String message;

  @override
  String toString() => message;
}
