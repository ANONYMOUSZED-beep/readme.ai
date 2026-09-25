import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/core/files/picked_book.dart';
import 'package:readme_ai/features/library/data/library_repository_impl.dart';

void main() {
  test('bookUploadForm preserves filename, bytes, and MIME type', () async {
    final bytes = Uint8List.fromList(const [37, 80, 68, 70]);
    final form = bookUploadForm(
      PickedBook(
        filename: 'guide.pdf',
        bytes: bytes,
        mimeType: 'application/pdf',
      ),
    );

    expect(form.files, hasLength(1));
    final entry = form.files.single;
    expect(entry.key, 'file');
    expect(entry.value.filename, 'guide.pdf');
    expect(entry.value.contentType?.toString(), 'application/pdf');
    expect(
      await entry.value.finalize().fold<List<int>>(<int>[], (all, chunk) {
        all.addAll(chunk);
        return all;
      }),
      bytes,
    );
  });
}
