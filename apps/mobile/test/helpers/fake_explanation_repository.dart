import 'dart:async';

import 'package:readme_ai/features/explanation/domain/explanation.dart';
import 'package:readme_ai/features/explanation/domain/explanation_repository.dart';
import 'package:readme_ai/features/explanation/domain/selection_type.dart';

/// In-memory [ExplanationRepository] for widget and unit tests.
class FakeExplanationRepository implements ExplanationRepository {
  FakeExplanationRepository();

  Explanation result = const Explanation(
    selectionType: SelectionType.word,
    explanation: 'A laptop is a portable computer you can use anywhere.',
    meaning: 'a small portable computer',
    example: 'Winston opened his laptop to write.',
  );

  /// When set, [explain] throws this.
  Object? error;

  /// When set, [explain] awaits this before returning (to test loading).
  Completer<void>? gate;

  int calls = 0;
  String? lastAnchor;
  String? lastEndAnchor;
  String? lastSelectedText;

  @override
  Future<Explanation> explain({
    required String bookId,
    required String anchor,
    required String endAnchor,
    required String selectedText,
  }) async {
    calls++;
    lastAnchor = anchor;
    lastEndAnchor = endAnchor;
    lastSelectedText = selectedText;
    if (gate != null) {
      await gate!.future;
    }
    if (error != null) {
      throw error!;
    }
    return result;
  }
}
