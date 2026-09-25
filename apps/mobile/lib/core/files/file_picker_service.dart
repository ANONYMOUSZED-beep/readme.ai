import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'picked_book.dart';

/// Abstraction over the platform file picker so the upload flow can be tested
/// without invoking native plugins.
abstract interface class FilePickerService {
  /// Prompt the user to pick a book file. Returns `null` if cancelled.
  Future<PickedBook?> pickBook();
}

/// [FilePickerService] backed by the `file_picker` plugin.
class FilePickerServiceImpl implements FilePickerService {
  const FilePickerServiceImpl();

  @override
  Future<PickedBook?> pickBook() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'epub', 'txt', 'md', 'markdown'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) {
      return null;
    }
    return PickedBook(filename: file.name, bytes: bytes);
  }
}

/// Provides the file picker. Overridden in tests with a fake.
final filePickerProvider = Provider<FilePickerService>(
  (ref) => const FilePickerServiceImpl(),
);
