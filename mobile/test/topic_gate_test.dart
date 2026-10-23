import 'package:balance_app/core/utils/markdown_utils.dart';
import 'package:balance_app/data/models/chat_models.dart';
import 'package:balance_app/data/services/topic_gate_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitSegments', () {
    test('is lossless for Chinese and English punctuation', () {
      const String text = '第一句。第二句！Third? Fourth; 换行\n结尾';
      final List<String> segments = splitSegments(text);
      expect(segments.join(), text);
    });

    test('keeps a trailing segment without terminator', () {
      expect(splitSegments('甲。乙'), <String>['甲。', '乙']);
    });
  });

  group('applyTopicMask', () {
    test('drops masked segments', () {
      final TopicGateMask mask = TopicGateMask(
        topic: '甲',
        keep: <bool>[true, false, true],
      );
      expect(applyTopicMask('甲。乙。丙。', mask), '甲。丙。');
    });

    test('fails open when mask length does not match', () {
      final TopicGateMask mask = TopicGateMask(
        topic: '甲',
        keep: <bool>[false],
      );
      expect(applyTopicMask('甲。乙。', mask), '甲。乙。');
    });

    test('returns the original when all segments are kept', () {
      final TopicGateMask mask = TopicGateMask(
        topic: '甲',
        keep: <bool>[true, true],
      );
      expect(applyTopicMask('甲。乙。', mask), '甲。乙。');
    });
  });

  group('rewriteCitations', () {
    test('rewrites reference markers outside code', () {
      expect(rewriteCitations('结论[ref_1]。'), '结论[1](#cite-1)。');
    });

    test('leaves inline code untouched', () {
      expect(rewriteCitations('`[ref_1]`'), '`[ref_1]`');
    });

    test('leaves fenced code untouched', () {
      expect(rewriteCitations('```\n[ref_1]\n```'), '```\n[ref_1]\n```');
    });
  });
}
