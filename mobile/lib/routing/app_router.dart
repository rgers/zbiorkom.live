import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/cities/cities_screen.dart';
import '../features/favorites/favorite_stops_screen.dart';
import '../features/filter/filter_screen.dart';
import '../features/map/city_map_screen.dart';
import '../features/routes/routes_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../state/app_providers.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      if (state.matchedLocation == '/') {
        final savedCity = ref.read(appSettingsProvider).selectedCityId;
        final bootstrap = ref.read(backendBootstrapProvider);
        if (savedCity != null &&
            savedCity.isNotEmpty &&
            bootstrap.findCity(savedCity) != null) {
          return '/$savedCity';
        }
        return '/cities';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/cities',
        builder: (context, state) => const CitiesScreen(),
      ),
      GoRoute(
        path: '/:city',
        builder: (context, state) {
          final city = state.pathParameters['city']!;
          return CityMapScreen(cityId: city);
        },
        routes: [
          GoRoute(
            path: 'search',
            builder: (context, state) {
              final city = state.pathParameters['city']!;
              return SearchScreen(city: city);
            },
          ),
          GoRoute(
            path: 'favoriteStops',
            builder: (context, state) {
              final city = state.pathParameters['city']!;
              return FavoriteStopsScreen(city: city);
            },
          ),
          GoRoute(
            path: 'filter',
            builder: (context, state) {
              final city = state.pathParameters['city']!;
              return FilterScreen(city: city);
            },
          ),
          GoRoute(
            path: 'routes',
            builder: (context, state) {
              final city = state.pathParameters['city']!;
              return RoutesScreen(city: city);
            },
          ),
          GoRoute(
            path: 'settings',
            builder: (context, state) {
              final city = state.pathParameters['city']!;
              return SettingsScreen(city: city);
            },
          ),
          GoRoute(
            path: 'stop/:stop',
            builder: (context, state) {
              final city = state.pathParameters['city']!;
              final stopId = state.pathParameters['stop']!;
              final queryCity = state.uri.queryParameters['city'];
              return CityMapScreen(
                cityId: city,
                overlayKind: CityOverlayKind.stop,
                entityId: stopId,
                queryCity: queryCity,
              );
            },
          ),
          GoRoute(
            path: 'station/:stop',
            builder: (context, state) {
              final city = state.pathParameters['city']!;
              final stopId = state.pathParameters['stop']!;
              final queryCity = state.uri.queryParameters['city'];
              return CityMapScreen(
                cityId: city,
                overlayKind: CityOverlayKind.station,
                entityId: stopId,
                queryCity: queryCity,
              );
            },
          ),
          GoRoute(
            path: 'vehicle/:vehicle',
            builder: (context, state) {
              final city = state.pathParameters['city']!;
              final vehicleId = state.pathParameters['vehicle']!;
              final queryCity = state.uri.queryParameters['city'];
              return CityMapScreen(
                cityId: city,
                overlayKind: CityOverlayKind.vehicle,
                entityId: vehicleId,
                queryCity: queryCity,
              );
            },
          ),
          GoRoute(
            path: 'trip/:trip',
            builder: (context, state) {
              final city = state.pathParameters['city']!;
              final tripId = state.pathParameters['trip']!;
              final queryCity = state.uri.queryParameters['city'];
              return CityMapScreen(
                cityId: city,
                overlayKind: CityOverlayKind.trip,
                entityId: tripId,
                queryCity: queryCity,
              );
            },
          ),
        ],
      ),
    ],
  );
});
