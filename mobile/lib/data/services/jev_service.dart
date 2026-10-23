import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SystemOneChannel {
  const SystemOneChannel({
    required this.id,
    required this.label,
    required this.endpoint,
    required this.model,
  });

  final String id;
  final String label;
  final String endpoint;
  final String model;
}

/// System One has exactly two supported channels. Endpoints and model ids
/// follow the official TypeSafe / OpenRouter documentation and must not be
/// mixed with each other's keys.
const List<SystemOneChannel> systemOneChannels = <SystemOneChannel>[
  SystemOneChannel(
    id: 'typesafe',
    label: 'Jev 官方',
    endpoint: 'https://api.typesafe.ai/v1/systemone',
    model: 'jev-latest',
  ),
  SystemOneChannel(
    id: 'openrouter',
    label: 'OpenRouter',
    endpoint: 'https://openrouter.ai/api/v1/systemone',
    model: '~typesafe/jev-latest',
  ),
];

const String systemOneDefaultEndpoint = 'https://api.typesafe.ai/v1/systemone';
const String systemOneDefaultModel = 'jev-latest';

SystemOneChannel? findSystemOneChannel(String id) {
  for (final SystemOneChannel channel in systemOneChannels) {
    if (channel.id == id) {
      return channel;
    }
  }
  return null;
}

class JevService {
  const JevService._();

  static const Duration _readTimeout = Duration(seconds: 20);

  /// Scores each segment's relevance to [topic].
  ///
  /// Business Rule: any failure (network, non-200, malformed body, count
  /// mismatch) returns null so the caller can fail open and keep the text.
  static Future<List<double>?> scoreSegments({
    required String topic,
    required List<String> segments,
    required String apiKey,
    required String endpoint,
    required String model,
  }) async {
    if (segments.isEmpty || apiKey.trim().isEmpty) {
      return null;
    }
    final http.Client client = http.Client();
    try {
      final http.Response response = await client
          .post(
            Uri.parse(endpoint),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${apiKey.trim()}',
              'Accept': 'application/json',
            },
            body: jsonEncode(_buildPayload(topic, segments, model)),
          )
          .timeout(_readTimeout);
      if (response.statusCode != 200) {
        debugPrint(
          'JevService: System One returned ${response.statusCode}; keeping every segment',
        );
        return null;
      }
      return _parseScores(jsonDecode(response.body), segments.length);
    } catch (error) {
      debugPrint(
        'JevService: System One call failed ($error); keeping every segment',
      );
      return null;
    } finally {
      client.close();
    }
  }

  static Map<String, dynamic> _buildPayload(
    String topic,
    List<String> segments,
    String model,
  ) {
    final Map<String, dynamic> stateSegments = <String, dynamic>{};
    final Map<String, dynamic> questions = <String, dynamic>{};
    for (int i = 0; i < segments.length; i++) {
      final String key = 'segment_$i';
      stateSegments[key] = segments[i];
      questions[key] = <String, String>{
        'type': 'noul',
        'instructions':
            'Does `segments.$key` stay on the conversation topic `topic`? '
                'Judge only relevance to the topic.',
      };
    }
    return <String, dynamic>{
      'model': model,
      'state': <String, dynamic>{
        'topic': topic,
        'segments': stateSegments,
      },
      'questions': questions,
    };
  }

  static List<double>? _parseScores(Object? parsed, int expected) {
    if (parsed is! Map) {
      return null;
    }
    final Object? answers = parsed['answers'];
    if (answers is! Map) {
      return null;
    }
    final List<double> out = <double>[];
    for (int i = 0; i < expected; i++) {
      final Object? answer = answers['segment_$i'];
      double score = 0;
      if (answer is Map) {
        final Object? value = answer['noul'];
        if (value is num) {
          score = value.toDouble();
        }
      }
      out.add(score);
    }
    return out;
  }
}
