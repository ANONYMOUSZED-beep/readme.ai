import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_providers.dart';
import '../config/app_config.dart';
import '../logging/app_logger.dart';
import 'auth_interceptor.dart';
import 'logging_interceptor.dart';
import 'timezone_interceptor.dart';

/// Default network timeout applied to connect and receive operations.
const _defaultTimeout = Duration(seconds: 15);

/// Provides a configured [Dio] instance for the application.
///
/// The base URL is derived from [appConfigProvider]; an [AuthInterceptor]
/// attaches the current user's bearer token and a [LoggingInterceptor] adds
/// observability. Feature data sources depend on this provider rather than
/// constructing their own client.
final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  final logger = ref.watch(loggerProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: _defaultTimeout,
      receiveTimeout: _defaultTimeout,
      headers: const {'Accept': 'application/json'},
    ),
  );

  dio.interceptors.addAll([
    AuthInterceptor(() => ref.read(authRepositoryProvider).idToken()),
    TimezoneInterceptor(),
    LoggingInterceptor(logger),
  ]);
  return dio;
});
