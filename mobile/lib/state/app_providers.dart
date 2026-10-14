import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../api/models.dart';
import '../core/api_config.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final apiClientProvider = Provider<ZbiorkomApiClient>((ref) {
  return ZbiorkomApiClient();
});

@immutable
class AppSettingsState {
  const AppSettingsState({
    required this.languageCode,
    required this.themeColorHex,
    required this.selectedCityId,
    required this.moveToLastLocation,
    required this.showBrigadeOnMarker,
    required this.showFleetOnMarker,
    required this.useDarkTiles,
    required this.apiBaseUrl,
    this.lastMapCenter,
    this.lastMapZoom,
  });

  final String languageCode;
  final String themeColorHex;
  final String? selectedCityId;
  final bool moveToLastLocation;
  final bool showBrigadeOnMarker;
  final bool showFleetOnMarker;
  final bool useDarkTiles;
  final String apiBaseUrl;
  final LatLng? lastMapCenter;
  final double? lastMapZoom;

  Color get seedColor {
    final cleaned = themeColorHex.replaceFirst('#', '').trim();
    final value = int.tryParse('FF$cleaned', radix: 16);
    return value != null ? Color(value) : const Color(0xFF276B2B);
  }

  AppSettingsState copyWith({
    String? languageCode,
    String? themeColorHex,
    String? selectedCityId,
    bool? moveToLastLocation,
    bool? showBrigadeOnMarker,
    bool? showFleetOnMarker,
    bool? useDarkTiles,
    String? apiBaseUrl,
    LatLng? lastMapCenter,
    double? lastMapZoom,
    bool clearLastMapPosition = false,
  }) {
    return AppSettingsState(
      languageCode: languageCode ?? this.languageCode,
      themeColorHex: themeColorHex ?? this.themeColorHex,
      selectedCityId: selectedCityId ?? this.selectedCityId,
      moveToLastLocation: moveToLastLocation ?? this.moveToLastLocation,
      showBrigadeOnMarker: showBrigadeOnMarker ?? this.showBrigadeOnMarker,
      showFleetOnMarker: showFleetOnMarker ?? this.showFleetOnMarker,
      useDarkTiles: useDarkTiles ?? this.useDarkTiles,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      lastMapCenter: clearLastMapPosition
          ? null
          : (lastMapCenter ?? this.lastMapCenter),
      lastMapZoom: clearLastMapPosition
          ? null
          : (lastMapZoom ?? this.lastMapZoom),
    );
  }
}

class AppSettingsNotifier extends StateNotifier<AppSettingsState> {
  AppSettingsNotifier(this._prefs) : super(_loadInitial(_prefs));

  final SharedPreferences _prefs;

  static AppSettingsState _loadInitial(SharedPreferences prefs) {
    final lat = prefs.getDouble('lastLat');
    final lon = prefs.getDouble('lastLon');
    final zoom = prefs.getDouble('lastZoom');
    final savedApiUrl = prefs.getString('apiBaseUrl') ?? ApiConfig.baseUrl;
    ApiConfig.setRuntimeBaseUrl(savedApiUrl);
    return AppSettingsState(
      languageCode: prefs.getString('language') ?? 'pl',
      themeColorHex: prefs.getString('themeColor') ?? '#276b2b',
      selectedCityId: prefs.getString('city'),
      moveToLastLocation: prefs.getBool('moveToLastLocation') ?? false,
      showBrigadeOnMarker: prefs.getBool('showBrigade') ?? true,
      showFleetOnMarker: prefs.getBool('showFleet') ?? false,
      useDarkTiles: prefs.getBool('useDarkTiles') ?? true,
      apiBaseUrl: savedApiUrl,
      lastMapCenter: (lat != null && lon != null) ? LatLng(lat, lon) : null,
      lastMapZoom: zoom,
    );
  }

  Future<void> setLanguage(String code) async {
    await _prefs.setString('language', code);
    state = state.copyWith(languageCode: code);
  }

  Future<void> setThemeColor(String hex) async {
    await _prefs.setString('themeColor', hex);
    state = state.copyWith(themeColorHex: hex);
  }

  Future<void> setSelectedCity(String cityId) async {
    final changed = state.selectedCityId != cityId;
    await _prefs.setString('city', cityId);
    if (changed) {
      await _prefs.remove('lastLat');
      await _prefs.remove('lastLon');
      await _prefs.remove('lastZoom');
    }
    state = state.copyWith(
      selectedCityId: cityId,
      clearLastMapPosition: changed,
    );
  }

  Future<void> setApiBaseUrl(String url) async {
    final cleaned = url.trim().isEmpty ? ApiConfig.baseUrl : url.trim();
    await _prefs.setString('apiBaseUrl', cleaned);
    ApiConfig.setRuntimeBaseUrl(cleaned);
    state = state.copyWith(apiBaseUrl: cleaned);
  }

  Future<void> setMoveToLastLocation(bool enabled) async {
    await _prefs.setBool('moveToLastLocation', enabled);
    state = state.copyWith(moveToLastLocation: enabled);
  }

  Future<void> setShowBrigadeOnMarker(bool enabled) async {
    await _prefs.setBool('showBrigade', enabled);
    state = state.copyWith(showBrigadeOnMarker: enabled);
  }

  Future<void> setShowFleetOnMarker(bool enabled) async {
    await _prefs.setBool('showFleet', enabled);
    state = state.copyWith(showFleetOnMarker: enabled);
  }

  Future<void> setUseDarkTiles(bool enabled) async {
    await _prefs.setBool('useDarkTiles', enabled);
    state = state.copyWith(useDarkTiles: enabled);
  }

  Future<void> saveMapPosition(LatLng center, double zoom) async {
    await _prefs.setDouble('lastLat', center.latitude);
    await _prefs.setDouble('lastLon', center.longitude);
    await _prefs.setDouble('lastZoom', zoom);
    state = state.copyWith(lastMapCenter: center, lastMapZoom: zoom);
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettingsState>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider);
      return AppSettingsNotifier(prefs);
    });

@immutable
class BackendBootstrapState {
  const BackendBootstrapState({
    this.cities = const [],
    this.isLoading = false,
    this.error,
    this.version = 0,
  });

  final List<City> cities;
  final bool isLoading;
  final BackendException? error;
  final int version;

  City? findCity(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final city in cities) {
      if (city.id == id) return city;
    }
    return null;
  }

  List<City> get visibleCities =>
      cities.where((city) => !city.virtual).toList();
}

class BackendBootstrapNotifier extends StateNotifier<BackendBootstrapState> {
  BackendBootstrapNotifier(this._apiClient)
    : super(const BackendBootstrapState(isLoading: true));

  final ZbiorkomApiClient _apiClient;

  Future<void> load() async {
    state = BackendBootstrapState(
      cities: state.cities,
      isLoading: true,
      version: state.version,
    );
    try {
      final loaded = await _apiClient.loadCities();
      state = BackendBootstrapState(
        cities: loaded,
        isLoading: false,
        version: state.version + 1,
      );
    } on BackendException catch (err) {
      state = BackendBootstrapState(
        cities: state.cities,
        isLoading: false,
        error: err,
        version: state.version,
      );
    } catch (_) {
      state = BackendBootstrapState(
        cities: state.cities,
        isLoading: false,
        error: const BackendException(BackendErrorKind.unknown),
        version: state.version,
      );
    }
  }
}

final backendBootstrapProvider =
    StateNotifierProvider<BackendBootstrapNotifier, BackendBootstrapState>((
      ref,
    ) {
      final api = ref.watch(apiClientProvider);
      return BackendBootstrapNotifier(api);
    });

@immutable
class CityFilterState {
  const CityFilterState({
    this.routes = const [],
    this.models = const [],
  });

  final List<TransitRoute> routes;
  final List<String> models;

  bool get isActive => routes.isNotEmpty || models.isNotEmpty;
}

class CityFilterNotifier extends StateNotifier<CityFilterState> {
  CityFilterNotifier() : super(const CityFilterState());

  void toggleRoute(TransitRoute route) {
    final exists = state.routes.any((r) => r.id == route.id);
    final updated = exists
        ? state.routes.where((r) => r.id != route.id).toList()
        : [...state.routes, route];
    state = CityFilterState(routes: updated, models: state.models);
  }

  void toggleModel(String model) {
    final exists = state.models.contains(model);
    final updated = exists
        ? state.models.where((m) => m != model).toList()
        : [...state.models, model];
    state = CityFilterState(routes: state.routes, models: updated);
  }

  void clear() {
    state = const CityFilterState();
  }
}

final cityFilterProvider =
    StateNotifierProvider.family<CityFilterNotifier, CityFilterState, String>((
      ref,
      city,
    ) {
      return CityFilterNotifier();
    });

class FavoriteStopsNotifier extends StateNotifier<List<FavoriteStopEntry>> {
  FavoriteStopsNotifier(this._prefs, this._city)
    : super(_load(_prefs, _city));

  final SharedPreferences _prefs;
  final String _city;

  static String _key(String city) => 'favorites_$city';

  static List<FavoriteStopEntry> _load(
    SharedPreferences prefs,
    String city,
  ) {
    final raw = prefs.getString(_key(city));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(FavoriteStopEntry.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  bool isFavorite(String stopId) {
    return state.any((s) => s.id == stopId);
  }

  Future<void> toggleStop(FavoriteStopEntry stop) async {
    final exists = isFavorite(stop.id);
    final updated = exists
        ? state.where((s) => s.id != stop.id).toList()
        : [...state, stop];
    state = updated;
    await _prefs.setString(
      _key(_city),
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
  }
}

final favoriteStopsProvider = StateNotifierProvider.family<
  FavoriteStopsNotifier,
  List<FavoriteStopEntry>,
  String
>((ref, city) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return FavoriteStopsNotifier(prefs, city);
});

final cityRoutesProvider = FutureProvider.family<List<TransitRoute>, String>((
  ref,
  city,
) async {
  final api = ref.watch(apiClientProvider);
  return api.fetchRoutes(city);
});

final cityModelsProvider = FutureProvider.family<List<String>, String>((
  ref,
  city,
) async {
  final api = ref.watch(apiClientProvider);
  return api.fetchVehicleModels(city);
});

final vehicleInfoProvider = FutureProvider.family<
  VehicleInfoDetails?,
  ({String city, String vehicleId})
>((ref, params) async {
  final api = ref.watch(apiClientProvider);
  return api.fetchVehicleInfo(params.city, params.vehicleId);
});

final stopDestinationsProvider = FutureProvider.family<
  List<TransitStop>,
  ({String city, String stopId})
>((ref, params) async {
  final api = ref.watch(apiClientProvider);
  return api.fetchStopDestinations(params.city, params.stopId);
});
