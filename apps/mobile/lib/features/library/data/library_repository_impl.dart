import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/files/picked_book.dart';
import '../domain/book.dart';
import '../domain/book_processing.dart';
import '../domain/library_repository.dart';
import 'book_dto.dart';

/// Build the multipart payload while preserving the selected file's metadata.
FormData bookUploadForm(PickedBook file) => FormData.fromMap({
  'file': MultipartFile.fromBytes(
    file.bytes,
    filename: file.filename,
    contentType: MediaType.parse(file.mimeType ?? 'application/octet-stream'),
  ),
});

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
  Future<Book> uploadBook(
    PickedBook file, {
    void Function(double progress)? onProgress,
  }) async {
    final formData = bookUploadForm(file);
    final response = await _dio.post<Map<String, dynamic>>(
      _basePath,
      data: formData,
      onSendProgress: onProgress == null
          ? null
          : (sent, total) {
              if (total > 0) onProgress((sent / total).clamp(0.0, 1.0));
            },
      options: Options(
        sendTimeout: _uploadSendTimeout,
        receiveTimeout: _uploadReceiveTimeout,
      ),
    );
    return BookDto.fromJson(response.data!).toDomain();
  }

  @override
  Future<BookProcessing?> getProcessing(String id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_basePath/$id/processing',
      );
      final data = response.data!;
      final errorCode = data['error_code'] as String?;
      return BookProcessing(
        wordCount: data['word_count'] as int? ?? 0,
        estimatedReadingMinutes: data['estimated_reading_minutes'] as int?,
        error: errorCode == null ? null : ProcessingError.fromApi(errorCode),
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<void> retryProcessing(String id) async {
    // Re-processing runs within this request, so allow as long as an upload.
    await _dio.post<void>(
      '$_basePath/$id/processing',
      options: Options(receiveTimeout: _uploadReceiveTimeout),
    );
  }

  @override
  Future<void> deleteBook(String id) async {
    await _dio.delete<void>('$_basePath/$id');
  }

  @override
  Future<Uint8List?> getCover(String id) async {
    try {
      final response = await _dio.get<List<int>>(
        '$_basePath/$id/cover',
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      return data == null ? null : Uint8List.fromList(data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }
}
