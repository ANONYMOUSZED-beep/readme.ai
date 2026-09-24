import 'package:json_annotation/json_annotation.dart';

import '../domain/book.dart';
import '../domain/book_status.dart';

part 'book_dto.g.dart';

/// Wire representation of a book, decoded from the backend JSON.
@JsonSerializable(createToJson: false)
class BookDto {
  const BookDto({
    required this.id,
    required this.title,
    required this.originalFilename,
    required this.mimeType,
    required this.fileSize,
    required this.status,
    required this.uploadedAt,
    this.totalPages,
    this.coverImageUrl,
    this.hasCover = false,
  });

  factory BookDto.fromJson(Map<String, dynamic> json) =>
      _$BookDtoFromJson(json);

  final String id;
  final String title;
  @JsonKey(name: 'original_filename')
  final String originalFilename;
  @JsonKey(name: 'mime_type')
  final String mimeType;
  @JsonKey(name: 'file_size')
  final int fileSize;
  final String status;
  @JsonKey(name: 'uploaded_at')
  final DateTime uploadedAt;
  @JsonKey(name: 'total_pages')
  final int? totalPages;
  @JsonKey(name: 'cover_image_url')
  final String? coverImageUrl;
  @JsonKey(name: 'has_cover', defaultValue: false)
  final bool hasCover;

  /// Map to the domain [Book].
  Book toDomain() => Book(
    id: id,
    title: title,
    originalFilename: originalFilename,
    mimeType: mimeType,
    fileSize: fileSize,
    status: BookStatus.fromApi(status),
    uploadedAt: uploadedAt,
    totalPages: totalPages,
    coverImageUrl: coverImageUrl,
    hasCover: hasCover,
  );
}
