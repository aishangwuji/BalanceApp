import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/chat_models.dart';
import 'jev_service.dart';

class TopicGateConfig {
  const TopicGateConfig({
    required this.enabled,
    required this.channel,
    required this.apiKey,
    required this.threshold,
    required this.endpoint,
    required this.model,
  });

  final bool enabled;
  final String channel;
  final String apiKey;
  final double threshold;
  final String endpoint;
  final String model;
}

const String _segmentBoundaries = '。！？!?；;\n';
const int _topicMaxChars = 400;
const int _topicStoreMaxChars = 120;

/// Splits on sentence terminators without losing characters.
///
/// Business Rule: `segments.join() == original`, otherwise mask indexes cannot
/// be aligned with the replayed text.
List<String> splitSegments(String text) {
  final List<String> segments = <String>[];
  int start = 0;
  for (int i = 0; i < text.length; i++) {
    if (_segmentBoundaries.contains(text[i])) {
      segments.add(text.substring(start, i + 1));
      start = i + 1;
    }
  }
  if (start < text.length) {
    segments.add(text.substring(start));
  }
  return segments;
}

/// Projects a stored mask onto content. Mismatched masks fail open.
String applyTopicMask(String content, TopicGateMask? mask) {
  if (mask == null) {
    return content;
  }
  final List<String> segments = splitSegments(content);
  if (mask.keep.length != segments.length) {
    return content;
  }
  if (mask.keep.every((bool keep) => keep)) {
    return content;
  }
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < segments.length; i++) {
    if (mask.keep[i]) {
      out.write(segments[i]);
    }
  }
  return out.toString();
}

class TopicGateService {
  const TopicGateService._();

  /// Annotates a just-persisted assistant message with a mask.
  ///
  /// Returns true when a mask was actually written. [topicText] must be the
  /// user message that produced this reply, not the current session topic.
  static Future<bool> annotate({
    required ChatMessage message,
    required String topicText,
    required TopicGateConfig config,
  }) async {
    if (!config.enabled || config.apiKey.trim().isEmpty) {
      return false;
    }
    if (!message.isAssistant || message.topicMask != null) {
      return false;
    }
    final String topic = topicText.trim();
    if (topic.isEmpty || message.content.trim().isEmpty) {
      return false;
    }

    final List<String> segments = splitSegments(message.content);
    final List<int> candidateIndexes = <int>[];
    final List<String> candidateTexts = <String>[];
    for (int i = 0; i < segments.length; i++) {
      if (segments[i].trim().isNotEmpty) {
        candidateIndexes.add(i);
        candidateTexts.add(segments[i]);
      }
    }
    if (candidateTexts.length < 2) {
      return false;
    }

    final List<double>? scores = await JevService.scoreSegments(
      topic: topic.substring(0, math.min(topic.length, _topicMaxChars)),
      segments: candidateTexts,
      apiKey: config.apiKey,
      endpoint: config.endpoint,
      model: config.model,
    );
    if (scores == null || scores.length != candidateTexts.length) {
      return false;
    }

    final List<bool> keep = List<bool>.filled(segments.length, true);
    int dropped = 0;
    for (int i = 0; i < candidateIndexes.length; i++) {
      final bool onTopic = scores[i] >= config.threshold;
      keep[candidateIndexes[i]] = onTopic;
      if (!onTopic) {
        dropped++;
      }
    }
    message.topicMask = TopicGateMask(
      topic: topic.substring(0, math.min(topic.length, _topicStoreMaxChars)),
      keep: keep,
    );
    debugPrint(
      'TopicGateService: masked $dropped/${segments.length} segments at write time',
    );
    return true;
  }
}
