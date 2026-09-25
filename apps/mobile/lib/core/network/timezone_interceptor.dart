import 'package:dio/dio.dart';

/// Sends the device's UTC offset (in minutes) with every request, so the
/// backend attributes reading to the reader's local day for streaks and daily
/// tasks rather than to UTC's.
class TimezoneInterceptor extends Interceptor {
  TimezoneInterceptor({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['X-Timezone-Offset'] = _now().timeZoneOffset.inMinutes
        .toString();
    handler.next(options);
  }
}
