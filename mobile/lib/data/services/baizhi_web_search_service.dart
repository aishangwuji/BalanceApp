import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_models.dart';

/// 百智云联网搜索（OpenAPI `/openapi/search`）。
///
/// 与 DeepSeek 服务端工具不同：这里由客户端先检索，再把摘要注入系统提示，
/// 来源直接挂在消息上；检索失败由调用方降级为普通回答。
class BaizhiWebSearchService {
  const BaizhiWebSearchService._();

  static const String _endpoint =
      'https://websearch.app.baizhi.cloud/openapi/search';
  static const int _maxResults = 8;
  static const Duration _timeout = Duration(seconds: 25);

  /// 检索网页；失败抛 [BaizhiSearchException]（调用方决定降级方式）。
  static Future<List<SearchSource>> search(String query, String apiKey) async {
    final String key = apiKey.trim();
    if (key.isEmpty) {
      throw const BaizhiSearchException('未配置百智云搜索 Key');
    }
    final String trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const <SearchSource>[];
    }
    try {
      final http.Response resp = await http
          .post(
            Uri.parse(_endpoint),
            headers: <String, String>{
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(<String, Object>{
              'query': trimmed,
              'count': _maxResults,
              'need_summary': true,
            }),
          )
          .timeout(_timeout);
      if (resp.statusCode != 200) {
        throw BaizhiSearchException('搜索服务返回状态码 ${resp.statusCode}');
      }
      final Object? decoded = jsonDecode(resp.body);
      if (decoded is! Map) {
        throw const BaizhiSearchException('搜索服务返回格式异常');
      }
      final Map<String, dynamic> rec = decoded.cast<String, dynamic>();
      final Object? code = rec['code'];
      if (code is num && code != 0) {
        final Object? message = rec['message'];
        throw BaizhiSearchException(
          message is String && message.isNotEmpty ? message : '搜索失败（code=$code）',
        );
      }
      return _parseResults(rec['data']);
    } on BaizhiSearchException {
      rethrow;
    } catch (error) {
      throw BaizhiSearchException('搜索请求失败: $error');
    }
  }

  /// 把来源拼成注入给模型的上下文段落（编号与来源胶囊顺序一致）。
  static String buildContext(List<SearchSource> sources) {
    if (sources.isEmpty) {
      return '';
    }
    final StringBuffer out = StringBuffer();
    out.writeln('以下是通过联网搜索得到的参考资料（可能不完整，请结合常识判断）：');
    for (int i = 0; i < sources.length; i++) {
      final SearchSource s = sources[i];
      final String site =
          (s.siteName ?? '').isNotEmpty ? s.siteName! : s.url;
      out.writeln('[${i + 1}] ${s.title}（$site）');
      if ((s.snippet ?? '').isNotEmpty) {
        out.writeln(s.snippet);
      }
      out.writeln(s.url);
    }
    out.writeln('回答时如使用了上述资料，请在句末用 [编号] 标注来源。');
    return out.toString();
  }

  static List<SearchSource> _parseResults(Object? data) {
    if (data is! Map) {
      return const <SearchSource>[];
    }
    final Object? results = data['results'];
    if (results is! List) {
      return const <SearchSource>[];
    }
    final List<SearchSource> out = <SearchSource>[];
    for (final Object? item in results) {
      final SearchSource? source = SearchSource.tryParse(<String, Object?>{
        if (item is Map) 'url': item['url'],
        if (item is Map) 'title': item['title'],
        if (item is Map) 'snippet': item['summary'],
        if (item is Map) 'siteName': item['site_name'],
        if (item is Map) 'publishedAt': item['published_at'],
      });
      if (source != null &&
          !out.any((SearchSource s) => s.url == source.url)) {
        out.add(source);
      }
    }
    return out;
  }
}

class BaizhiSearchException implements Exception {
  const BaizhiSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}
