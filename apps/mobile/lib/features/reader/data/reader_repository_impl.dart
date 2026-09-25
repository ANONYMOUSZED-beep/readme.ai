import 'package:dio/dio.dart';

import '../domain/book_content.dart';
import '../domain/bookmark.dart';
import '../domain/reader_repository.dart';
import '../domain/reading_progress.dart';
import '../domain/recent_read.dart';
import 'reader_dtos.dart';

/// [ReaderRepository] backed by the ReadMe.ai HTTP API via [Dio].
class ReaderRepositoryImpl implements ReaderRepository {
  const ReaderRepositoryImpl(this._dio);

  static const _base = '/api/v1/books';

  final Dio _dio;

  @override
  Future<BookContent> getContent(String bookId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '$_base/$bookId/content',
    );
    return BookContentDto.fromJson(response.data!).toDomain();
  }

  @override
  Future<ReadingProgress?> getProgress(String bookId) async {
    final response = await _dio.get<Map<String, dynamic>?>(
      '$_base/$bookId/progress',
    );
    final data = response.data;
    if (data == null) {
      return null;
    }
    return ReadingProgressDto.fromJson(data).toDomain();
  }

  @override
  Future<ReadingProgress> saveProgress(
    String bookId, {
    required String currentPosition,
    required double progressPercentage,
    required int readingTimeSeconds,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '$_base/$bookId/progress',
      data: {
        'current_position': currentPosition,
        'progress_percentage': progressPercentage,
        'reading_time_seconds': readingTimeSeconds,
      },
    );
    return ReadingProgressDto.fromJson(response.data!).toDomain();
  }

  @override
  Future<List<RecentRead>> listRecent() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/reading/recent',
    );
    final items = (response.data?['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return items
        .map((json) => RecentReadDto.fromJson(json).toDomain())
        .toList();
  }

  @override
  Future<List<Bookmark>> listBookmarks(String bookId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '$_base/$bookId/bookmarks',
    );
    final items = (response.data?['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return items.map((json) => BookmarkDto.fromJson(json).toDomain()).toList();
  }

  @override
  Future<Bookmark> createBookmark(
    String bookId, {
    required String anchor,
    String? label,
  }) async {
    final data = <String, dynamic>{'anchor': anchor};
    if (label != null) {
      data['label'] = label;
    }
    final response = await _dio.post<Map<String, dynamic>>(
      '$_base/$bookId/bookmarks',
      data: data,
    );
    return BookmarkDto.fromJson(response.data!).toDomain();
  }

  @override
  Future<void> deleteBookmark(String bookId, String bookmarkId) async {
    await _dio.delete<void>('$_base/$bookId/bookmarks/$bookmarkId');
  }
}
