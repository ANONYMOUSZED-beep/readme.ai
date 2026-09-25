import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readme_ai/core/network/timezone_interceptor.dart';

void main() {
  test('sends the device UTC offset in minutes', () {
    final now = DateTime.now();
    final options = RequestOptions(path: '/api/v1/activity/summary');

    TimezoneInterceptor(
      now: () => now,
    ).onRequest(options, RequestInterceptorHandler());

    expect(
      options.headers['X-Timezone-Offset'],
      '${now.timeZoneOffset.inMinutes}',
    );
  });
}
