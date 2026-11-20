import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_models.dart';
import '../models/provider.dart';

class ChatException implements Exception {
  const ChatException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ChatStreamEvent {
  const ChatStreamEvent({
    this.content = '',
    this.reasoning = '',
    this.done = false,
    this.searchHint = '',
    this.sources = const <SearchSource>[],
    this.citations = const <CitationRange>[],
    this.title = '',
  });

  final String content;
  final String reasoning;
  final bool done;
  /// 检索过程提示（server_tool_event）；空串表示本块没有搜索事件。
  final String searchHint;
  /// 本块新出现的来源（已按 url 去重由调用方合并）。
  final List<SearchSource> sources;
  /// 正文引用区间（delta.annotations）。
  final List<CitationRange> citations;
  /// 会话标题（仅首轮声明 title 时下发）。
  final String title;

  bool get hasPayload => content.isNotEmpty || reasoning.isNotEmpty;
}

class ChatRequestOptions {
  const ChatRequestOptions({
    required this.providerId,
    required this.apiKey,
    required this.model,
    required this.messages,
    this.temperature,
    this.systemPrompt,
    this.enableThinking = false,
    this.reasoningEffort = 'high',
    this.enableWebSearch = false,
  });

  final String providerId;
  final String apiKey;
  final String model;
  final List<ChatMessage> messages;
  final double? temperature;
  final String? systemPrompt;
  final bool enableThinking;
  final String reasoningEffort;
  /// 联网搜索：仅 DeepSeek 声明服务端工具 deepseek_web_search。
  final bool enableWebSearch;
}

/// OpenAI-compatible streaming engine.
///
/// Protocol contract (ported from the HarmonyOS client):
/// 1. `[DONE]` is the only completion signal; `finish_reason` is ignored.
/// 2. `delta.content` and `delta.reasoning_content` are append-only.
/// 3. The terminal usage chunk has an empty `choices` array and is skipped.
/// 4. History is stateless per request and truncated by count + chars.
class ChatService {
  const ChatService._();

  static const int _maxHistoryMessages = 20;
  static const int _maxHistoryChars = 12000;

  static const Duration _connectTimeout = Duration(seconds: 15);
  static const Duration _readTimeout = Duration(seconds: 90);

  static Stream<ChatStreamEvent> streamChat(ChatRequestOptions options) async* {
    final ProviderDefinition? def = findProvider(options.providerId);
    if (def == null) {
      throw ChatException('未知的服务商: ${options.providerId}');
    }
    if (options.apiKey.trim().isEmpty) {
      throw const ChatException('未配置 API Key，请先配置');
    }
    if (options.model.trim().isEmpty) {
      throw const ChatException('未选择模型');
    }

    final Uri uri = Uri.parse('${def.baseUrl}${def.chatEndpoint}');
    final http.Client client = http.Client();
    try {
      final http.Request request = http.Request('POST', uri)
        ..headers.addAll(<String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${options.apiKey.trim()}',
          'api-key': options.apiKey.trim(),
          'Accept': 'text/event-stream',
        })
        ..body = jsonEncode(_buildPayload(options, def, true));

      final http.StreamedResponse response =
          await client.send(request).timeout(_connectTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final String body = await response.stream.bytesToString();
        throw ChatException(
          '服务商返回状态码 ${response.statusCode}: ${_truncate(body)}',
        );
      }

      bool sawDone = false;
      final Stream<String> lines = response.stream
          .timeout(_readTimeout)
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final String rawLine in lines) {
        final String line = rawLine.trim();
        if (!line.startsWith('data:')) {
          continue;
        }
        final String data = line.substring(5).trim();
        if (data == '[DONE]') {
          sawDone = true;
          break;
        }
        final ChatStreamEvent? event = _parseChunk(data);
        if (event != null && event.hasPayload) {
          yield event;
        }
      }
      if (!sawDone) {
        // Stream closed without [DONE]: keep the partial content, but let the
        // caller know the reply ended abnormally.
        yield const ChatStreamEvent(done: true);
      } else {
        yield const ChatStreamEvent(done: true);
      }
    } on TimeoutException {
      throw const ChatException('网络请求超时，请重试');
    } on http.ClientException catch (error) {
      throw ChatException('网络请求失败: ${error.message}');
    } finally {
      client.close();
    }
  }

  static ChatStreamEvent? _parseChunk(String data) {
    try {
      final Object? parsed = jsonDecode(data);
      if (parsed is! Map) {
        return null;
      }
      final Object? choices = parsed['choices'];
      if (choices is! List || choices.isEmpty) {
        return null;
      }
      final Object? choice = choices.first;
      if (choice is! Map) {
        return null;
      }
      final Object? delta = choice['delta'];
      if (delta is! Map) {
        return null;
      }
      final Object? content = delta['content'];
      final Object? reasoning = delta['reasoning_content'];
      final String hint = _searchHint(choice['server_tool_event']);
      final List<CitationRange> citations = _parseAnnotations(delta['annotations']);
      final List<SearchSource> sources = <SearchSource>[];
      for (final CitationRange cite in citations) {
        if (!sources.any((SearchSource s) => s.url == cite.url)) {
          sources.add(SearchSource(url: cite.url, title: cite.title));
        }
      }
      final Object? titleRaw = delta['title'];
      final String title = titleRaw is String ? titleRaw.trim() : '';
      return ChatStreamEvent(
        content: content is String ? content : '',
        reasoning: reasoning is String ? reasoning : '',
        searchHint: hint,
        sources: sources,
        citations: citations,
        title: title,
      );
    } catch (_) {
      // Ignore keep-alive or malformed single lines.
      return null;
    }
  }

  /// System prompt first, then history newest-first truncation.
  ///
  /// Business Rule: assistant history is projected through its stored topic
  /// mask; mismatched masks fail open. `reasoning_content` is replayed for
  /// preserved-thinking providers.
  static List<Map<String, String>> buildApiMessages(
    List<ChatMessage> messages,
    String? systemPrompt,
  ) {
    final List<Map<String, String>> out = <Map<String, String>>[];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      out.add(<String, String>{
        'role': 'system',
        'content': systemPrompt.trim(),
      });
    }
    final List<Map<String, String>> candidates = <Map<String, String>>[];
    for (final ChatMessage message in messages) {
      if (!message.isUser && !message.isAssistant) {
        continue;
      }
      final String replay = message.content;
      final String reasoning = message.reasoningContent ?? '';
      if (replay.isEmpty && reasoning.isEmpty) {
        continue;
      }
      final Map<String, String> item = <String, String>{
        'role': ChatMessage.roleToWire(message.role),
        'content': replay,
      };
      if (message.isAssistant && reasoning.isNotEmpty) {
        item['reasoning_content'] = reasoning;
      }
      candidates.add(item);
    }

    final int start = candidates.length > _maxHistoryMessages
        ? candidates.length - _maxHistoryMessages
        : 0;
    final List<Map<String, String>> kept = <Map<String, String>>[];
    int used = 0;
    for (int i = candidates.length - 1; i >= start; i--) {
      final Map<String, String> c = candidates[i];
      final int total = c['content']!.length +
          c['role']!.length +
          8 +
          (c['reasoning_content']?.length ?? 0);
      if (kept.isNotEmpty && used + total > _maxHistoryChars) {
        break;
      }
      kept.insert(0, c);
      used += total;
    }
    out.addAll(kept);
    return out;
  }

  static Map<String, dynamic> _buildPayload(
    ChatRequestOptions options,
    ProviderDefinition def,
    bool isStream,
  ) {
    final Map<String, dynamic> payload = <String, dynamic>{
      'model': options.model,
      'messages': buildApiMessages(options.messages, options.systemPrompt),
      'stream': isStream,
    };
    // 联网搜索：仅 DeepSeek 声明服务端工具（搜索/抓取由服务端完成）。
    if (options.enableWebSearch && options.providerId == 'deepseek') {
      payload['tools'] = <Map<String, String>>[
        <String, String>{'type': 'deepseek_web_search'},
      ];
    }
    final bool thinkingOn =
        options.enableThinking && def.supportsThinking;
    final String model = options.model.toLowerCase();

    if (options.providerId == 'kimi') {
      if (model.startsWith('kimi-k3')) {
        payload['reasoning_effort'] = options.reasoningEffort;
      } else if (model.contains('kimi-k2.7')) {
        // Always-thinking model: no thinking flag and no temperature.
      } else if (model.startsWith('kimi-k2.6')) {
        payload['thinking'] = <String, String>{
          'type': thinkingOn ? 'enabled' : 'disabled',
        };
      } else {
        payload['temperature'] = options.temperature ?? 0.7;
      }
      return payload;
    }

    if (options.providerId == 'mimo') {
      payload['thinking'] = <String, String>{
        'type': thinkingOn ? 'enabled' : 'disabled',
      };
      if (!thinkingOn) {
        payload['temperature'] = options.temperature ?? 0.7;
      }
      return payload;
    }

    if (thinkingOn) {
      payload['thinking'] = <String, String>{'type': 'enabled'};
      payload['reasoning_effort'] = options.reasoningEffort;
    } else {
      if (def.supportsThinking) {
        payload['thinking'] = <String, String>{'type': 'disabled'};
      }
      payload['temperature'] = options.temperature ?? 0.7;
    }
    return payload;
  }

  static String _truncate(String text) =>
      text.length <= 500 ? text : '${text.substring(0, 500)}…';

  /// server_tool_event → 一行中文进度提示；未知事件返回空串。
  static String _searchHint(Object? raw) {
    if (raw is! Map) {
      return '';
    }
    final Object? phase = raw['phase'];
    if (phase == 'started') {
      return '正在联网搜索…';
    }
    if (phase == 'completed') {
      return '已搜索';
    }
    return '';
  }

  /// 解析 delta.annotations 中的 url_citation；偏移是 Unicode 码点。
  static List<CitationRange> _parseAnnotations(Object? raw) {
    if (raw is! List) {
      return const <CitationRange>[];
    }
    final List<CitationRange> out = <CitationRange>[];
    for (final Object? item in raw) {
      if (item is! Map || item['type'] != 'url_citation') {
        continue;
      }
      final Object? payload = item['url_citation'];
      if (payload is! Map) {
        continue;
      }
      final Object? url = payload['url'];
      if (url is! String || !(url.startsWith('http://') || url.startsWith('https://'))) {
        continue;
      }
      final Object? start = payload['start_index'];
      final Object? end = payload['end_index'];
      if (start is! num || end is! num) {
        continue;
      }
      final Object? title = payload['title'];
      out.add(
        CitationRange(
          url: url,
          title: title is String && title.isNotEmpty ? title : url,
          start: start.toInt(),
          end: end.toInt(),
        ),
      );
    }
    return out;
  }
}
