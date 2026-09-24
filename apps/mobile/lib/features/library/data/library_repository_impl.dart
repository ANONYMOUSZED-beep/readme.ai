import 'package:dio/dio.dart';

import '../../../core/files/picked_book.dart';
import '../domain/book.dart';
import '../domain/library_repository.dart';
import '../domain/processing_report.dart';
import 'book_dto.dart';

/// [LibraryRepository] backed by the ReadMe.ai HTTP API via [Dio].
///
/// The bearer token is attached by the shared `AuthInterceptor`, so this class
/// is concerned only with endpoints and (de)serialization.
class LibraryRepositoryImpl implements LibraryRepository {
  const LibraryRepositoryImpl(this._dio);

  static const _basePath = '/api/v1/books';

  /// Uploads can be large and the server processes the book (PDF/EPUB parsing)
  /// before responding, so they get far more time than the 15s default.
  static const _uploadSendTimeout = Duration(minutes: 2);
  static const _uploadReceiveTimeout = Duration(minutes: 3);

  final Dio _dio;

  @override
  Future<List<Book>> listBooks() async {
    final response = await _dio.get<Map<String, dynamic>>(_basePath);
    final items = (response.data?['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return items.map((json) => BookDto.fromJson(json).toDomain()).toList();
  }

  @override
  Future<Book> getBook(String id) async {
    final response = await _dio.get<Map<String, dynamic>>('$_basePath/$id');
    return BookDto.fromJson(response.data!).toDomain();
  }

  @override
  Future<Book> uploadBook(PickedBook file) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(file.bytes, filename: file.filename),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      _basePath,
      data: formData,
      options: Options(
        sendTimeout: _uploadSendTimeout,
        receiveTimeout: _uploadReceiveTimeout,
      ),
    );
    return BookDto.fromJson(response.data!).toDomain();
  }

  @override
  Future<void> deleteBook(String id) async {
    await _dio.delete<void>('$_basePath/$id');
  }

  @override
  Future<ProcessingReport?> getProcessingReport(String id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_basePath/$id/processing',
      );
      return _toReport(response.data!);
    } on DioException catch (error) {
      // 404 here means "never processed", not a missing book.
      if (error.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<ProcessingReport> reprocessBook(String id) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$_basePath/$id/processing',
      options: Options(receiveTimeout: _uploadReceiveTimeout),
    );
    return _toReport(response.data!);
  }

  static ProcessingReport _toReport(Map<String, dynamic> json) {
    final message = json['error_message'];
    return ProcessingReport(
      completed: json['status'] == 'COMPLETED',
      errorMessage: message is String && message.isNotEmpty ? message : null,
    );
  }
}
