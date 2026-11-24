/// Most words shown for one sentence: more than this does not fit on a
/// phone at a readable size, and is more than most symbol users can take in
/// at once.
const maxSentenceWords = 12;

/// Splits a spoken or typed sentence into the words to show as symbols:
/// punctuation is dropped, order and spelling are kept, and at most
/// [maxSentenceWords] words are returned.
///
/// `"Wir gehen jetzt essen, okay?"` -> `[Wir, gehen, jetzt, essen, okay]`.
List<String> sentenceWords(String sentence) {
  return sentence
      .split(RegExp(r'\s+'))
      .map((w) => w.replaceAll(RegExp(r'[^\p{L}\p{N}\-]', unicode: true), ''))
      .map((w) => w.replaceAll(RegExp(r'^-+|-+$'), ''))
      .where((w) => w.isNotEmpty)
      .take(maxSentenceWords)
      .toList();
}
