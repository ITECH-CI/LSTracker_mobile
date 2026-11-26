import 'dart:async';

import 'package:dio/dio.dart';
import 'package:lstracker/app_config/app_config.dart';
import 'package:lstracker/data/services/token_interceptor.dart';
import 'package:lstracker/data/stores/auth_store.dart';

class DioClient {
  DioClient._();
  static final DioClient instance = DioClient._();

  final Dio dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBase,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );

  bool _initialized = false;
  AuthStore? _store;

  Future<void> initWithAuth(AuthStore store) async {
    _store = store;
    if (!_initialized) {
      dio.interceptors.add(TokenInterceptor(dio, store));
      _initialized = true;
    }
    final token = await store.accessToken;
    if (token != null && token.isNotEmpty) {
      dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      dio.options.headers.remove('Authorization');
    }
  }

  /// Si tu gères le refresh ici (au lieu de TokenInterceptor), utilise ce helper.
  Future<Response<dynamic>?> tryRefreshAndRetry(RequestOptions failed) async {
    final store = _store;
    if (store == null) return null;

    final refresh = await store.refreshToken;
    if (refresh == null || refresh.isEmpty) return null;

    try {
      final res = await dio.post(
        AppConfig.refreshPath,
        data: {'refresh_token': refresh},
        options: Options(
          headers: {
            'Authorization': null, // refresh sans bearer
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );

      final data = res.data is Map ? (res.data as Map) : {};
      final newAccess = (data['access_token'] ?? '').toString();
      final newRefresh = (data['refresh_token'] ?? refresh).toString();

      if (newAccess.isNotEmpty) {
        // Ecrit en secure storage
        await store.writeTokens(accessToken: newAccess, refreshToken: newRefresh);

        // Rejoue la requête d’origine avec le nouveau token
        final opts = Options(
          method: failed.method,
          headers: Map<String, dynamic>.from(failed.headers)
            ..['Authorization'] = 'Bearer $newAccess',
          responseType: failed.responseType,
          contentType: failed.contentType,
          sendTimeout: failed.sendTimeout,
          receiveTimeout: failed.receiveTimeout,
          extra: failed.extra,
          followRedirects: failed.followRedirects,
          listFormat: failed.listFormat,
          validateStatus: failed.validateStatus,
        );

        return await dio.request<dynamic>(
          failed.path,
          data: failed.data,
          queryParameters: failed.queryParameters,
          options: opts,
          cancelToken: failed.cancelToken,
          onReceiveProgress: failed.onReceiveProgress,
          onSendProgress: failed.onSendProgress,
        );
      }
    } catch (_) {
      // Laisse la 401 remonter si le refresh échoue
    }
    return null;
  }
}