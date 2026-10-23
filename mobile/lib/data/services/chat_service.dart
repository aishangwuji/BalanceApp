import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_models.dart';
import '../models/provider.dart';
import 'topic_gate_service.dart';

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
  });

  final String content;
  final String reasoning;
  final bool done;

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
  });

  final String providerId;
  final String apiKey;
  final String model;
  final List<ChatMessage> messages;
  final double? temperature;
  final String? systemPrompt;
  final bool enableThinking;
  final String reasoningEffort;
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
      return ChatStreamEvent(
        content: content is String ? content : '',
        reasoning: reasoning is String ? reasoning : '',
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
      final String replay = message.isAssistant
          ? applyTopicMask(message.content, message.topicMask)
          : message.content;
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
}
