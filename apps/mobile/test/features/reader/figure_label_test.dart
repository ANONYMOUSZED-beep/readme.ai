import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/reader/presentation/rendering/renderers/figure_label.dart';

void main() {
  group('numbers stated by the caption', () {
    test('reads the common figure and table forms', () {
      expect(FigureLabel.fromCaption('Figure 5. The pipeline'), 'Figure 5');
      expect(FigureLabel.fromCaption('Figure 12: Results'), 'Figure 12');
      expect(FigureLabel.fromCaption('Fig. 3 — Overview'), 'Figure 3');
      expect(FigureLabel.fromCaption('Fig 7'), 'Figure 7');
      expect(FigureLabel.fromCaption('Table 3. Query plans'), 'Table 3');
      expect(FigureLabel.fromCaption('Tbl. 2'), 'Table 2');
    });

    test('is case insensitive and tolerates leading space', () {
      expect(FigureLabel.fromCaption('  figure 4. lower'), 'Figure 4');
      expect(FigureLabel.fromCaption('FIGURE 9'), 'Figure 9');
      expect(FigureLabel.fromCaption('TABLE 1: caps'), 'Table 1');
    });

    test('keeps chapter-qualified numbers intact', () {
      expect(
        FigureLabel.fromCaption('Figure 4.2 Nested numbering'),
        'Figure 4.2',
      );
      expect(FigureLabel.fromCaption('Figure 10-3 Dash form'), 'Figure 10-3');
      expect(FigureLabel.fromCaption('Table 2.11.4 Deep'), 'Table 2.11.4');
    });

    test('recognises the other caption families', () {
      expect(FigureLabel.fromCaption('Image 2 of the set'), 'Image 2');
      expect(FigureLabel.fromCaption('Photo 8'), 'Photo 8');
      expect(FigureLabel.fromCaption('Chart 6 — Growth'), 'Chart 6');
      expect(FigureLabel.fromCaption('Diagram 1'), 'Diagram 1');
      expect(FigureLabel.fromCaption('Listing 14: SQL'), 'Listing 14');
      expect(FigureLabel.fromCaption('Exhibit 3'), 'Exhibit 3');
      expect(FigureLabel.fromCaption('Plate IV'), 'Plate IV');
    });

    test('accepts plural forms used by some publishers', () {
      expect(FigureLabel.fromCaption('Figures 5'), 'Figure 5');
      expect(FigureLabel.fromCaption('Tables 2'), 'Table 2');
    });
  });

  group('captions that state no number', () {
    test('returns null rather than inventing one', () {
      expect(FigureLabel.fromCaption('The processing pipeline'), isNull);
      expect(FigureLabel.fromCaption('Figure of speech in prose'), isNull);
      expect(FigureLabel.fromCaption(''), isNull);
      expect(FigureLabel.fromCaption(null), isNull);
      expect(FigureLabel.fromCaption('   '), isNull);
    });

    test('only matches at the start of the caption', () {
      expect(FigureLabel.fromCaption('See Figure 5 above'), isNull);
    });

    test('an unrelated leading word is not a family', () {
      expect(FigureLabel.fromCaption('Section 4 introduces'), isNull);
      expect(FigureLabel.fromCaption('Chapter 2 begins'), isNull);
    });
  });

  group('resolve', () {
    test('prefers the caption and falls back otherwise', () {
      expect(
        FigureLabel.resolve('Figure 5. Pipeline', fallback: 'Figure'),
        'Figure 5',
      );
      expect(
        FigureLabel.resolve('No number here', fallback: 'Figure'),
        'Figure',
      );
      expect(FigureLabel.resolve(null, fallback: 'Table'), 'Table');
    });

    test('is deterministic', () {
      for (var attempt = 0; attempt < 3; attempt++) {
        expect(
          FigureLabel.resolve('Fig. 4.2 — Nested', fallback: 'Figure'),
          'Figure 4.2',
        );
      }
    });
  });
}
