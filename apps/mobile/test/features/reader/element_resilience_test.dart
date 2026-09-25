import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/features/reader/data/element_dtos.dart';
import 'package:readme_ai/features/reader/data/reader_repository_impl.dart';
import 'package:readme_ai/features/reader/domain/reader_element.dart';
import 'package:readme_ai/features/reader/domain/reader_span.dart';

/// A Dio adapter returning a canned body, so the client is tested without I/O.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body, {this.statusCode = 200});

  final String body;
  final int statusCode;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _window(List<Object?> elements) => {
  'book_id': 'b1',
  'start': 0,
  'end': 200,
  'character_count': 200,
  'truncated': false,
  'elements': elements,
};

void main() {
  group('malformed payload isolation', () {
    test('an element missing required fields is skipped, not fatal', () {
      final window = ElementWindowDecoder.decode(
        _window([
          {
            'id': 'p1',
            'parent_id': 'sec',
            'type': 'paragraph',
            'order_index': 0,
            'sequence': 0,
            'start_offset': 0,
            'end_offset': 30,
            'payload': <String, dynamic>{},
          },
          // No id.
          {'type': 'paragraph', 'order_index': 1, 'sequence': 1},
          // No type.
          {'id': 'p3', 'order_index': 2, 'sequence': 2},
          // Non-numeric ordering.
          {
            'id': 'p4',
            'type': 'paragraph',
            'order_index': 'first',
            'sequence': 3,
          },
          {
            'id': 'p5',
            'parent_id': 'sec',
            'type': 'paragraph',
            'order_index': 4,
            'sequence': 4,
            'start_offset': 40,
            'end_offset': 70,
            'payload': <String, dynamic>{},
          },
        ]),
      );

      // The two well-formed paragraphs survive; three are counted as skipped.
      expect(window.elements.map((element) => element.id), ['p1', 'p5']);
      expect(window.skipped, 3);
      expect(window.isComplete, isFalse);
    });

    test('non-object entries in the list are skipped', () {
      final window = ElementWindowDecoder.decode(
        _window([
          'not an element',
          42,
          null,
          {
            'id': 'p',
            'type': 'paragraph',
            'order_index': 0,
            'sequence': 0,
            'payload': <String, dynamic>{},
          },
        ]),
      );

      expect(window.elements, hasLength(1));
      expect(window.skipped, 3);
    });

    test('a wrongly typed payload degrades that element only', () {
      final window = ElementWindowDecoder.decode(
        _window([
          {
            'id': 'c',
            'type': 'code_block',
            'order_index': 0,
            'sequence': 0,
            'payload': 'not a map',
          },
          {
            'id': 'p',
            'type': 'paragraph',
            'order_index': 1,
            'sequence': 1,
            'payload': <String, dynamic>{},
          },
        ]),
      );

      final code = window.elements.first as CodeBlockElement;
      expect(code.language, isNull);
      expect(window.elements, hasLength(2));
      expect(window.skipped, 0);
    });

    test('a nonsensical span decodes as no span rather than failing', () {
      final window = ElementWindowDecoder.decode(
        _window([
          {
            'id': 'p',
            'type': 'paragraph',
            'order_index': 0,
            'sequence': 0,
            'start_offset': 90,
            'end_offset': 10,
            'payload': <String, dynamic>{},
          },
        ]),
      );

      expect(window.elements.single.span, isNull);
      expect(window.skipped, 0);
    });

    test(
      'required type-specific fields falling back keep the element readable',
      () {
        final window = ElementWindowDecoder.decode(
          _window([
            // A hyperlink with no target, a formula with no representation, an
            // image with no identifier, a caption with no target.
            {
              'id': 'h',
              'type': 'hyperlink',
              'order_index': 0,
              'sequence': 0,
              'payload': <String, dynamic>{},
            },
            {
              'id': 'f',
              'type': 'formula',
              'order_index': 1,
              'sequence': 1,
              'start_offset': 0,
              'end_offset': 8,
              'payload': <String, dynamic>{},
            },
            {
              'id': 'img',
              'type': 'image',
              'order_index': 2,
              'sequence': 2,
              'payload': <String, dynamic>{},
            },
            {
              'id': 'cap',
              'type': 'caption',
              'order_index': 3,
              'sequence': 3,
              'start_offset': 10,
              'end_offset': 20,
              'payload': <String, dynamic>{},
            },
          ]),
        );

        expect(window.skipped, 0);
        expect(window.elements.every((e) => e is UnknownElement), isTrue);
        // They still reach the page as text rather than disappearing.
        expect(window.elements.every((e) => e.isReadable), isTrue);
        expect(window.elements.map((e) => (e as UnknownElement).rawType), [
          'hyperlink',
          'formula',
          'image',
          'caption',
        ]);
      },
    );
  });

  group('forward compatibility', () {
    test('an unknown element type decodes as UnknownElement', () {
      final window = ElementWindowDecoder.decode(
        _window([
          {
            'id': 'd',
            'parent_id': 'sec',
            'type': 'interactive_diagram',
            'order_index': 0,
            'sequence': 0,
            'start_offset': 10,
            'end_offset': 40,
            'page_number': 3,
            'payload': {'layers': 4, 'interactive': true},
            'text': null,
          },
        ]),
      );

      final element = window.elements.single as UnknownElement;
      expect(element.rawType, 'interactive_diagram');
      expect(element.span, const ReaderSpan(10, 40));
      expect(element.pageNumber, 3);
      // Unknown elements are readable so their characters still render.
      expect(element.isReadable, isTrue);
      expect(window.skipped, 0);
    });

    test('unrecognised payload and window keys are ignored', () {
      final window = ElementWindowDecoder.decode({
        'book_id': 'b1',
        'start': 0,
        'end': 100,
        'character_count': 100,
        'truncated': false,
        'next_cursor': 'someday',
        'elements': [
          {
            'id': 'p',
            'type': 'paragraph',
            'order_index': 0,
            'sequence': 0,
            'start_offset': 0,
            'end_offset': 30,
            'payload': {'future_field': 'ignored'},
            'inline_runs': ['also ignored'],
          },
        ],
      });

      expect(window.elements.single, isA<ParagraphElement>());
      expect(window.skipped, 0);
    });
  });

  group('ordering and relationships', () {
    test('elements are ordered by document sequence regardless of arrival', () {
      final window = ElementWindowDecoder.decode(
        _window([
          {
            'id': 'p2',
            'type': 'paragraph',
            'order_index': 1,
            'sequence': 5,
            'payload': <String, dynamic>{},
          },
          {
            'id': 'ch',
            'type': 'chapter',
            'order_index': 0,
            'sequence': 1,
            'payload': <String, dynamic>{},
          },
          {
            'id': 'p1',
            'type': 'paragraph',
            'order_index': 0,
            'sequence': 4,
            'payload': <String, dynamic>{},
          },
          {
            'id': 'sec',
            'type': 'section',
            'order_index': 0,
            'sequence': 2,
            'payload': <String, dynamic>{},
          },
        ]),
      );

      expect(window.elements.map((element) => element.id), [
        'ch',
        'sec',
        'p1',
        'p2',
      ]);
    });

    test('parent relationships and canonical spans survive decoding', () {
      final window = ElementWindowDecoder.decode(
        _window([
          {
            'id': 'ch',
            'parent_id': 'doc',
            'type': 'chapter',
            'order_index': 0,
            'sequence': 0,
            'start_offset': 0,
            'end_offset': 200,
            'payload': <String, dynamic>{},
          },
          {
            'id': 'sec',
            'parent_id': 'ch',
            'type': 'section',
            'order_index': 0,
            'sequence': 1,
            'start_offset': 0,
            'end_offset': 200,
            'payload': <String, dynamic>{},
          },
          {
            'id': 'p',
            'parent_id': 'sec',
            'type': 'paragraph',
            'order_index': 0,
            'sequence': 2,
            'start_offset': 0,
            'end_offset': 30,
            'payload': <String, dynamic>{},
          },
        ]),
      );

      final byId = {for (final e in window.elements) e.id: e};
      expect(byId['ch']!.parentId, 'doc');
      expect(byId['sec']!.parentId, 'ch');
      expect(byId['p']!.parentId, 'sec');
      expect(byId['p']!.span, const ReaderSpan(0, 30));
      expect(byId['ch']!.span, const ReaderSpan(0, 200));
    });
  });

  group('repository and API client', () {
    test(
      'requests the documented path and range, and decodes the body',
      () async {
        final adapter = _StubAdapter(
          '{"book_id":"b1","start":0,"end":20000,"character_count":200,'
          '"truncated":false,"elements":[{"id":"p","parent_id":"sec",'
          '"type":"paragraph","order_index":0,"sequence":3,"start_offset":0,'
          '"end_offset":30,"page_number":1,"payload":{},"text":null}]}',
        );
        final dio = Dio()..httpClientAdapter = adapter;
        final repository = ReaderRepositoryImpl(dio);

        final window = await repository.getElements('b1', start: 0, end: 20000);

        expect(adapter.lastRequest?.path, '/api/v1/books/b1/content/elements');
        expect(adapter.lastRequest?.queryParameters, {
          'start': 0,
          'end': 20000,
        });
        expect(adapter.lastRequest?.method, 'GET');
        expect(window.characterCount, 200);
        expect(window.elements.single, isA<ParagraphElement>());
      },
    );

    test('a body-less response yields an empty window for the range', () async {
      final dio = Dio()..httpClientAdapter = _StubAdapter('null');
      final repository = ReaderRepositoryImpl(dio);

      final window = await repository.getElements('b1', start: 40, end: 90);

      expect(window.isEmpty, isTrue);
      expect(window.start, 40);
      expect(window.end, 90);
    });

    test('transport failures propagate for the caller to degrade', () async {
      final dio = Dio()
        ..httpClientAdapter = _StubAdapter(
          '{"detail":"nope"}',
          statusCode: 500,
        );
      final repository = ReaderRepositoryImpl(dio);

      await expectLater(
        repository.getElements('b1', start: 0, end: 10),
        throwsA(isA<DioException>()),
      );
    });
  });
}
