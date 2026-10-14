import 'package:dio/dio.dart';
import '../core/api_config.dart';
import 'models.dart';

enum BackendErrorKind { network, server, unknown }

class BackendException implements Exception {
  const BackendException(this.kind, [this.message]);

  final BackendErrorKind kind;
  final String? message;

  @override
  String toString() => 'BackendException($kind${message != null ? ': $message' : ''})';
}

class ZbiorkomApiClient {
  ZbiorkomApiClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: ApiConfig.baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: const {'Accept': 'application/json'},
            ),
          );

  final Dio _dio;

  Future<bool> isOnline() async {
    try {
      await _dio.get<void>(
        ApiConfig.connectivityProbeUrl,
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          validateStatus: (_) => true,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<City>> loadCities() async {
    Response<dynamic> response;
    try {
      response = await _dio.getUri<dynamic>(ApiConfig.api6Uri());
    } catch (_) {
      final online = await isOnline();
      throw BackendException(
        online ? BackendErrorKind.server : BackendErrorKind.network,
      );
    }

    final data = response.data;
    if (response.statusCode != 200 || data is! Map<String, dynamic>) {
      throw const BackendException(BackendErrorKind.server);
    }

    if (data['error'] != null) {
      throw BackendException(
        BackendErrorKind.server,
        data['error']?.toString(),
      );
    }

    final rawCities = data['cities'];
    if (rawCities is! List || rawCities.isEmpty) {
      throw const BackendException(BackendErrorKind.server);
    }

    return rawCities
        .whereType<Map<String, dynamic>>()
        .map(City.fromJson)
        .where((city) => city.id.isNotEmpty)
        .toList();
  }

  Future<T> getFromApi<T>({
    required String city,
    required String endpoint,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
    required T Function(dynamic json) parser,
  }) async {
    final uri = ApiConfig.api6Uri('$city/$endpoint', query);
    final response = await _dio.getUri<dynamic>(
      uri,
      cancelToken: cancelToken,
    );
    return parser(response.data);
  }

  Future<List<TransitRoute>> fetchRoutes(
    String city, {
    CancelToken? cancelToken,
  }) {
    return getFromApi<List<TransitRoute>>(
      city: city,
      endpoint: 'routes',
      cancelToken: cancelToken,
      parser: (data) {
        if (data is! List) return const [];
        return data
            .whereType<List<dynamic>>()
            .map(TransitRoute.fromTuple)
            .toList();
      },
    );
  }

  Future<List<String>> fetchVehicleModels(
    String city, {
    CancelToken? cancelToken,
  }) {
    return getFromApi<List<String>>(
      city: city,
      endpoint: 'vehicles/models',
      cancelToken: cancelToken,
      parser: (data) {
        if (data is! List) return const [];
        return data.map((e) => e.toString()).toList();
      },
    );
  }

  Future<VehicleInfoDetails?> fetchVehicleInfo(
    String city,
    String vehicleId, {
    CancelToken? cancelToken,
  }) {
    return getFromApi<VehicleInfoDetails?>(
      city: city,
      endpoint: 'vehicles/vehicle/${Uri.encodeComponent(vehicleId)}',
      cancelToken: cancelToken,
      parser: (data) {
        if (data is List && data.isNotEmpty) {
          return VehicleInfoDetails.fromTuple(data);
        }
        return null;
      },
    );
  }

  Future<List<TransitStop>> fetchStopDestinations(
    String city,
    String stopId, {
    CancelToken? cancelToken,
  }) {
    return getFromApi<List<TransitStop>>(
      city: city,
      endpoint: 'stops/${Uri.encodeComponent(stopId)}/destinations',
      cancelToken: cancelToken,
      parser: (data) {
        if (data is! List) return const [];
        return data
            .whereType<List<dynamic>>()
            .map(TransitStop.fromTuple)
            .toList();
      },
    );
  }

  Future<SearchResultsBundle> searchCity(
    String city,
    String query, {
    CancelToken? cancelToken,
  }) {
    return getFromApi<SearchResultsBundle>(
      city: city,
      endpoint: 'search',
      query: {'query': query},
      cancelToken: cancelToken,
      parser: (data) {
        if (data is Map<String, dynamic>) {
          if (data['error'] is String) {
            throw BackendException(
              BackendErrorKind.server,
              data['error'] as String,
            );
          }
          return SearchResultsBundle.fromJson(data);
        }
        return const SearchResultsBundle(
          results: [],
          groups: [],
          groupNames: [],
        );
      },
    );
  }
}
