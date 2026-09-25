import 'package:dio/dio.dart';

import '../error/failure.dart';

/// Translates a low-level [DioException] into the application's typed
/// [Failure] taxonomy, keeping Dio specifics out of the rest of the codebase.
///
/// For error responses, the backend's own message (from its
/// `{"error": {"message": ...}}` envelope) is preserved: those messages are
/// written for end users (e.g. "Uploaded file exceeds the maximum allowed
/// size.") and are far more helpful than a generic status description.
Failure mapDioException(DioException exception) {
  switch (exception.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
    case DioExceptionType.connectionError:
      return const Failure.network(
        message: 'Could not reach the server. Check your connection.',
      );
    case DioExceptionType.cancel:
      return const Failure.cancelled(message: 'The request was cancelled.');
    case DioExceptionType.badResponse:
      return Failure.server(
        message:
            _envelopeMessage(exception.response?.data) ??
            'The server returned an error.',
        statusCode: exception.response?.statusCode,
      );
    case DioExceptionType.badCertificate:
    case DioExceptionType.unknown:
      return const Failure.unexpected(
        message: 'An unexpected network error occurred.',
      );
  }
}

/// A message suitable for showing the user for [error], or [fallback].
///
/// Connectivity problems and client errors (4xx) carry specific, actionable
/// messages; anything else (server faults, non-network exceptions) uses the
/// caller's context-specific [fallback] such as "Upload failed".
String describeError(Object error, {required String fallback}) {
  if (error is! DioException) {
    return fallback;
  }
  return switch (mapDioException(error)) {
    NetworkFailure(:final message) => message,
    ServerFailure(:final message, :final statusCode)
        when statusCode != null && statusCode >= 400 && statusCode < 500 =>
      message,
    _ => fallback,
  };
}

String? _envelopeMessage(Object? data) {
  if (data is Map<String, dynamic>) {
    final error = data['error'];
    if (error is Map<String, dynamic>) {
      final message = error['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
    }
  }
  return null;
}
