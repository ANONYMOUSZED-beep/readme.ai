import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/core/files/file_picker_service.dart';

void main() {
  test('bookMimeType maps supported extensions case-insensitively', () {
    expect(bookMimeType('guide.pdf'), 'application/pdf');
    expect(bookMimeType('NOTES.TXT'), 'text/plain');
    expect(bookMimeType('Novel.EPUB'), 'application/epub+zip');
    expect(bookMimeType('notes.md'), 'text/markdown');
    expect(bookMimeType('book.bin'), 'application/octet-stream');
  });
}
