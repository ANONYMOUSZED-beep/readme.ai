import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/core/error/failure.dart';
import 'package:readme_ai/core/network/dio_error_mapper.dart';

final _options = RequestOptions(path: '/api/v1/books');

DioException _response(int statusCode, Object? data) => DioException(
  requestOptions: _options,
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: _options,
    statusCode: statusCode,
    data: data,
  ),
);

Map<String, dynamic> _envelope(String message) => {
  'error': {
    'code': 'payload_too_large',
    'message': message,
    'details': <String, dynamic>{},
    'request_id': 'abc',
  },
};

void main() {
  group('mapDioException', () {
    test('keeps the backend envelope message for error responses', () {
      final failure = mapDioException(
        _response(413, _envelope('Uploaded file is too big.')),
      );

      expect(
        failure,
        const Failure.server(
          message: 'Uploaded file is too big.',
          statusCode: 413,
        ),
      );
    });

    test('falls back to a generic message without an envelope', () {
      final failure = mapDioException(_response(502, '<html>bad gateway'));

      expect(failure, isA<ServerFailure>());
      expect(failure.message, 'The server returned an error.');
    });

    test('maps connectivity problems to a network failure', () {
      final failure = mapDioException(
        DioException(
          requestOptions: _options,
          type: DioExceptionType.connectionError,
        ),
      );

      expect(failure, isA<NetworkFailure>());
    });
  });

  group('describeError', () {
    test('shows the server message for client errors', () {
      expect(
        describeError(
          _response(413, _envelope('Uploaded file is too big.')),
          fallback: 'Upload failed.',
        ),
        'Uploaded file is too big.',
      );
    });

    test('uses the fallback for server faults', () {
      expect(
        describeError(
          _response(500, _envelope('An unexpected error occurred.')),
          fallback: 'Upload failed.',
        ),
        'Upload failed.',
      );
    });

    test('explains connectivity problems', () {
      expect(
        describeError(
          DioException(
            requestOptions: _options,
            type: DioExceptionType.receiveTimeout,
          ),
          fallback: 'Upload failed.',
        ),
        'Could not reach the server. Check your connection.',
      );
    });

    test('uses the fallback for non-network errors', () {
      expect(
        describeError(StateError('boom'), fallback: 'Upload failed.'),
        'Upload failed.',
      );
    });
  });
}
