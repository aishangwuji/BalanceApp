import 'package:balance_app/data/models/chat_models.dart';
import 'package:balance_app/state/chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('injectCitationMarkers', () {
    test('inserts marker at the end index of each citation', () {
      const String content = '甲说了一句话。乙回应了。';
      final List<SearchSource> sources = <SearchSource>[
        const SearchSource(url: 'https://a.com', title: 'A'),
        const SearchSource(url: 'https://b.com', title: 'B'),
      ];
      final List<CitationRange> cites = <CitationRange>[
        const CitationRange(
          url: 'https://a.com',
          title: 'A',
          start: 0,
          end: 7,
        ),
        const CitationRange(
          url: 'https://b.com',
          title: 'B',
          start: 7,
          end: 12,
        ),
      ];
      final String out = injectCitationMarkers(content, cites, sources);
      expect(out, contains('[1](#cite-1)'));
      expect(out, contains('[2](#cite-2)'));
      // 标记必须落在引用文本之后，正文顺序不变。
      expect(out.indexOf('甲说了一句话。'), lessThan(out.indexOf('[1](#cite-1)')));
    });

    test('skips citations whose source is unknown or offset is negative', () {
      final String out = injectCitationMarkers(
        'abc',
        <CitationRange>[
          const CitationRange(url: 'https://x.com', title: 'X', start: 0, end: 1),
          const CitationRange(url: 'https://a.com', title: 'A', start: 0, end: -1),
        ],
        <SearchSource>[const SearchSource(url: 'https://a.com', title: 'A')],
      );
      expect(out, 'abc');
    });
  });

  group('SearchSource.tryParse', () {
    test('rejects non-http urls and keeps title fallback', () {
      expect(
        SearchSource.tryParse(<String, Object?>{'url': 'file:///x'}),
        isNull,
      );
      final SearchSource? source =
          SearchSource.tryParse(<String, Object?>{'url': 'https://a.com'});
      expect(source?.title, 'https://a.com');
    });
  });
}
