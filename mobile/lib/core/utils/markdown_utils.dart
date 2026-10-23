/// Rewrites `[ref_N]` citations into clickable links.
///
/// Business Rule: fenced and inline code must be left untouched, otherwise a
/// code sample containing `[ref_1]` would unexpectedly become a link.
String rewriteCitations(String source) {
  final StringBuffer out = StringBuffer();
  int index = 0;
  bool inFence = false;
  bool inInlineCode = false;
  while (index < source.length) {
    if (source.startsWith('```', index)) {
      inFence = !inFence;
      out.write('```');
      index += 3;
      continue;
    }
    if (!inFence && source[index] == '`') {
      inInlineCode = !inInlineCode;
      out.write('`');
      index++;
      continue;
    }
    if (!inFence && !inInlineCode && source.startsWith('[ref_', index)) {
      final int close = source.indexOf(']', index + 5);
      if (close > index) {
        final String number = source.substring(index + 5, close);
        if (int.tryParse(number) != null) {
          out.write('[$number](#cite-$number)');
          index = close + 1;
          continue;
        }
      }
    }
    out.write(source[index]);
    index++;
  }
  return out.toString();
}

/// Returns the citation number for `#cite-N`, otherwise null.
int? citationIndex(String href) {
  if (!href.startsWith('#cite-')) {
    return null;
  }
  return int.tryParse(href.substring(6));
}

bool isSafeExternalUrl(String href) {
  final Uri? uri = Uri.tryParse(href);
  if (uri == null) {
    return false;
  }
  return uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'mailto';
}
