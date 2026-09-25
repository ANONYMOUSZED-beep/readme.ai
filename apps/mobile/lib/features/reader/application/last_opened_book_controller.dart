import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Remembers the book most recently opened in the reader this session, so the
/// library can offer to pick it back up.
class LastOpenedBookController extends Notifier<String?> {
  @override
  String? build() => null;

  /// Record that [bookId] was opened in the reader.
  void open(String bookId) => state = bookId;
}

/// Exposes the id of the last book opened in the reader (null if none yet).
final lastOpenedBookProvider =
    NotifierProvider<LastOpenedBookController, String?>(
      LastOpenedBookController.new,
    );
