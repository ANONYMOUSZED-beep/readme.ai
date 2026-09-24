import 'package:dio/dio.dart';

import '../domain/explanation.dart';
import '../domain/explanation_repository.dart';
import 'explanation_dto.dart';

/// [ExplanationRepository] backed by the ReadMe.ai explanation API via [Dio].
class ExplanationRepositoryImpl implements ExplanationRepository {
  const ExplanationRepositoryImpl(this._dio);

  /// The backend waits on a language model (30s by default, longer on slow
  /// hardware); the global 15s receive timeout would give up first.
  static const _receiveTimeout = Duration(seconds: 90);

  final Dio _dio;

  @override
  Future<Explanation> explain({
    required String bookId,
    required String anchor,
    required String endAnchor,
    required String selectedText,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/books/$bookId/explain',
      data: {
        'anchor': anchor,
        'end_anchor': endAnchor,
        'selected_text': selectedText,
      },
      options: Options(receiveTimeout: _receiveTimeout),
    );
    return ExplanationDto.fromJson(response.data!).toDomain();
  }
}
