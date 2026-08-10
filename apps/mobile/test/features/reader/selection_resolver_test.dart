import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/reader/domain/character_anchor.dart';
import 'package:readme_ai/features/reader/domain/reader_span.dart';
import 'package:readme_ai/features/reader/presentation/rendering/selection_resolver.dart';

const _resolver = SelectionResolver();

/// A page holding one of every readable element, joined as canonical text.
const _paragraph = 'Reading comes first. Structure serves reading.';
const _code = 'SELECT id\n  FROM users;';
const _quote = 'A book is a mirror.';
const _item = 'First guideline';
const _caption = 'Figure 1. A diagram.';
const _footnote = '1. A clarifying note.';
const _formula = 'E = mc^2';
const _cell = 'Header';
const _tail = 'A closing paragraph.';

final String _page = [
  _paragraph,
  _code,
  _quote,
  _item,
  _caption,
  _footnote,
  _formula,
  _cell,
  _tail,
].join('\n\n');

ReaderSpan? _resolve(String selected, {int pageStart = 0, int? hint}) =>
    _resolver.resolve(
      pageText: _page,
      pageStartOffset: pageStart,
      selectedText: selected,
      hintOffset: hint,
    );

/// The canonical range a fragment occupies in the page.
ReaderSpan _expected(String fragment, {int pageStart = 0}) {
  final codeUnit = _page.indexOf(fragment);
  return ReaderSpan(
    pageStart + CharacterAnchor.fromCodeUnit(_page, codeUnit),
    pageStart + CharacterAnchor.fromCodeUnit(_page, codeUnit + fragment.length),
  );
}

void main() {
  group('readable element types', () {
    test('resolves selections in every readable element', () {
      for (final fragment in [
        _paragraph,
        _code,
        _quote,
        _item,
        _caption,
        _footnote,
        _formula,
        _cell,
      ]) {
        expect(_resolve(fragment), _expected(fragment), reason: fragment);
      }
    });

    test('resolves a word inside a paragraph', () {
      expect(_resolve('Structure'), _expected('Structure'));
    });

    test('resolves a line inside a code block', () {
      // Leading whitespace is trimmed from the selection, exactly as the
      // previous implementation did, so the submitted text is unchanged.
      final span = _resolve('  FROM users;');

      expect(span, _expected('FROM users;'));
      expect(
        CharacterAnchor.substring(_page, span!.start, span.end),
        'FROM users;',
      );
    });

    test('a code selection keeps its internal whitespace', () {
      final span = _resolve(_code);

      expect(
        CharacterAnchor.substring(_page, span!.start, span.end),
        contains('\n  '),
      );
    });

    test('resolves multi-line code selections', () {
      expect(_resolve(_code), _expected(_code));
    });
  });

  group('cross-element selections', () {
    test('a selection spanning three elements is one contiguous range', () {
      final selected = _page.substring(
        _page.indexOf(_paragraph),
        _page.indexOf(_quote) + _quote.length,
      );

      final span = _resolve(selected);

      expect(span!.start, _expected(_paragraph).start);
      expect(span.end, _expected(_quote).end);
      // Contiguous: it covers the separators between the elements too.
      expect(span.length, CharacterAnchor.length(selected));
    });

    test('resolves when rendering dropped the separators', () {
      // A cross-element selection as the UI may report it: blocks joined by a
      // single space rather than the canonical blank line.
      const selected = '$_item $_caption';

      final span = _resolve(selected);

      expect(span!.start, _expected(_item).start);
      expect(span.end, _expected(_caption).end);
    });

    test('collapsed matching does not include trailing whitespace', () {
      final span = _resolve('$_quote $_item');

      expect(span!.end, _expected(_item).end);
    });
  });

  group('canonical offsets', () {
    test('offsets are relative to the page start', () {
      const pageStart = 5000;

      expect(
        _resolve(_quote, pageStart: pageStart),
        _expected(_quote, pageStart: pageStart),
      );
    });

    test('astral characters count as single scalars', () {
      const text = '😀😃😄 A curious reader studies every sentence.';

      final span = _resolver.resolve(
        pageText: text,
        pageStartOffset: 0,
        selectedText: 'curious reader',
      );

      expect(
        CharacterAnchor.substring(text, span!.start, span.end),
        'curious reader',
      );
      // Three emoji, a space, 'A' and a space precede the match — six scalars,
      // not the nine code units a UTF-16 count would give.
      expect(span.start, 6);
    });

    test('trims the selection exactly as before', () {
      final span = _resolve('   $_quote  \n');

      expect(span, _expected(_quote));
    });
  });

  group('refuses rather than guessing', () {
    test('text absent from the page resolves to nothing', () {
      expect(_resolve('this sentence is not in the book'), isNull);
    });

    test('empty and whitespace-only selections resolve to nothing', () {
      expect(_resolve(''), isNull);
      expect(_resolve('   \n  '), isNull);
    });

    test('an empty page resolves to nothing', () {
      expect(
        _resolver.resolve(
          pageText: '',
          pageStartOffset: 0,
          selectedText: 'anything',
        ),
        isNull,
      );
    });

    test('ambiguous repeats with no hint resolve to nothing', () {
      const page = 'alpha beta alpha beta alpha';

      expect(
        _resolver.resolve(
          pageText: page,
          pageStartOffset: 0,
          selectedText: 'alpha',
        ),
        isNull,
      );
    });

    test('a hint disambiguates repeats deterministically', () {
      const page = 'alpha beta alpha beta alpha';

      final first = _resolver.resolve(
        pageText: page,
        pageStartOffset: 0,
        selectedText: 'alpha',
        hintOffset: 0,
      );
      final last = _resolver.resolve(
        pageText: page,
        pageStartOffset: 0,
        selectedText: 'alpha',
        hintOffset: 24,
      );

      expect(first, const ReaderSpan(0, 5));
      expect(last, const ReaderSpan(22, 27));
    });

    test('never returns a range outside the page', () {
      final span = _resolve(_tail);

      expect(span!.start, greaterThanOrEqualTo(0));
      expect(span.end, lessThanOrEqualTo(CharacterAnchor.length(_page)));
    });
  });

  group('determinism', () {
    test('repeated resolution returns identical ranges', () {
      for (var attempt = 0; attempt < 3; attempt++) {
        expect(_resolve(_code), _expected(_code));
        expect(_resolve('$_item $_caption'), isNotNull);
      }
    });

    test('resolution does not depend on the hint when unambiguous', () {
      expect(_resolve(_quote, hint: 0), _resolve(_quote, hint: 900));
    });
  });
}
