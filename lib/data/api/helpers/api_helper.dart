import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/utils/sharedPrefs_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/error.dart';
import '../../../main.dart';
import '../user_api.dart';

interface class ApiHelper {

  static const String BASEURL = 'https://runbackendrun-6d3g5hh5.b4a.run/api/';

  static Future<Response?> makeRequest(
    String url,
    String method, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParams,
  }) async {
    final remoteApi = RemoteApi(url);
    await remoteApi.setJwt();

    try {
      Response? response;
      switch (method) {
        case 'GET':
          response = await remoteApi.dio.get(
            url,
            queryParameters: queryParams,
          );
          break;
        case 'POST':
          response = await remoteApi.dio.post(
            url,
            data: data,
            queryParameters: queryParams,
          );
          break;
        case 'PUT':
          response = await remoteApi.dio.put(
            url,
            data: data,
            queryParameters: queryParams,
          );
          break;
        case 'DELETE':
          response = await remoteApi.dio.delete(
            url,
            queryParameters: queryParams,
          );
          break;
      }
      return response;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        return remoteApi.handleUnauthorizedError(error, data, queryParams);
      }
      throw Failure(message: error.toString());
    }
  }
}

interface class RemoteApi {
  late String url;
  late Dio dio;
  late SharedPreferences prefs;

  RemoteApi(this.url) {
    dio = Dio();
    initCache();
  }

  Future<void> initCache() async {
    prefs = await SharedPreferences.getInstance();

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final cacheKey = options.uri.toString();

        final cachedResponse = prefs.getString(cacheKey);

        if (options.method == 'GET' && cachedResponse != null) {
          final cacheTimestamp = prefs.getInt('$cacheKey:timestamp') ?? 0;

          final currentTimestamp = DateTime.now().millisecondsSinceEpoch;
          final expirationDuration = const Duration(days: 1).inMilliseconds;

          if (currentTimestamp - cacheTimestamp <= expirationDuration) {
            handler.resolve(Response(
              data: jsonDecode(cachedResponse),
              statusCode: 200,
              requestOptions: options,
            ));
            return;
          } else {
            prefs.remove(cacheKey);
            prefs.remove('$cacheKey:timestamp');
          }
        }

        if (options.method == 'POST' ||
            options.method == 'PUT' ||
            options.method == 'DELETE') {
          prefs.remove('${url}all');
          prefs.remove('${url}all:timestamp');
        }

        handler.next(options);
      },
      onResponse: (response, handler) async {
        final cacheKey = response.requestOptions.uri.toString();
        final jsonResponse = jsonEncode(response.data);
        await prefs.setString(cacheKey, jsonResponse);

        final currentTimestamp = DateTime.now().millisecondsSinceEpoch;
        await prefs.setInt('$cacheKey:timestamp', currentTimestamp);

        handler.next(response);
      },
      onError: (DioException error, ErrorInterceptorHandler handler) async {
        handler.next(error);
      },
    ));
  }

  Future<void> setJwt() async {
    final jwt = await PrefsUtils.getJwt();
    if (jwt != null) {
      dio.options.headers['Authorization'] = 'Bearer $jwt';
    }
  }


  Future<Response?> handleUnauthorizedError(DioException error,
      Map<String, dynamic>? data, Map<String, dynamic>? queryParameters) async {
    try {
      String? jwt = await UserApi.refreshToken();
      try {
        var headers = error.requestOptions.headers;
        headers['Authorization'] = 'Bearer $jwt';
        return await dio.request(
          queryParameters: queryParameters,
          data: data,
          error.requestOptions.path,
          options: Options(
            method: error.requestOptions.method,
            headers: headers,
            contentType: error.requestOptions.contentType,
            responseType: error.requestOptions.responseType,
          ),
        );
      } on DioException catch (_) {
        navigatorKey.currentState?.pushReplacementNamed('/login');
      }
    } on DioException {
      navigatorKey.currentState?.pushReplacementNamed('/login');
    }
    return null;
  }
}
