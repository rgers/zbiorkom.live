import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../api/models.dart';
import '../../api/sse_client.dart';
import '../../core/transit_tools.dart';
import '../../l10n/app_strings.dart';
import '../../state/app_providers.dart';
import '../stop/stop_departures_sheet.dart';
import '../trip/trip_sheet.dart';

enum CityOverlayKind { none, stop, station, vehicle, trip }

class MapInitialPayload {
  const MapInitialPayload({
    required this.stops,
    this.suggestedCity,
  });

  final List<TransitStop> stops;
  final String? suggestedCity;
}

class MapRealtimePayload {
  const MapRealtimePayload({
    required this.vehicles,
    required this.dots,
  });

  final List<VehiclePosition> vehicles;
  final List<DotVehicle> dots;

  bool get useDots => dots.isNotEmpty;
}

class CityMapScreen extends ConsumerStatefulWidget {
  const CityMapScreen({
    super.key,
    required this.cityId,
    this.overlayKind = CityOverlayKind.none,
    this.entityId,
    this.queryCity,
  });

  final String cityId;
  final CityOverlayKind overlayKind;
  final String? entityId;
  final String? queryCity;

  @override
  ConsumerState<CityMapScreen> createState() => _CityMapScreenState();
}

class _CityMapScreenState extends ConsumerState<CityMapScreen> {
  final MapController _mapController = MapController();
  Timer? _cameraDebounce;
  SseSubscriptionController<MapRealtimePayload, MapInitialPayload>?
  _mapStreamController;
  SseStreamSnapshot<MapRealtimePayload, MapInitialPayload> _mapSnapshot =
      const SseStreamSnapshot(isLoading: true);

  List<LatLng> _activeTripPolyline = const [];
  LatLng? _userLocation;
  String? _currentBoundsStr;
  double _currentZoom = 16.0;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCityCamera();
    });
  }

  @override
  void didUpdateWidget(covariant CityMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cityId != widget.cityId) {
      _activeTripPolyline = const [];
      _initializeCityCamera(forceCityCenter: true);
    }
  }

  void _initializeCityCamera({bool forceCityCenter = false}) {
    final bootstrap = ref.read(backendBootstrapProvider);
    final settings = ref.read(appSettingsProvider);
    final city = bootstrap.findCity(widget.cityId);

    final useSavedLocation =
        !forceCityCenter &&
        settings.moveToLastLocation &&
        settings.lastMapCenter != null &&
        settings.selectedCityId == widget.cityId;

    final initialCenter = useSavedLocation
        ? settings.lastMapCenter!
        : (city?.location ?? City.defaultLocation);
    final initialZoom =
        (useSavedLocation && settings.lastMapZoom != null)
        ? settings.lastMapZoom!
        : (city?.zoom ?? 16.0);

    _currentZoom = initialZoom;
    if (_mapReady) {
      try {
        _mapController.move(initialCenter, initialZoom);
      } catch (_) {}
      _updateMapStreamFromBounds();
    } else {
      // Fallback bounds around initialCenter before FlutterMap layout completes
      const latDelta = 0.015;
      const lonDelta = 0.025;
      _currentBoundsStr = [
        (initialCenter.longitude - lonDelta).toStringAsFixed(5),
        (initialCenter.latitude - latDelta).toStringAsFixed(5),
        (initialCenter.longitude + lonDelta).toStringAsFixed(5),
        (initialCenter.latitude + latDelta).toStringAsFixed(5),
      ].join(',');
      _reconnectMapStream();
    }
  }

  void _updateMapStreamFromBounds() {
    LatLngBounds? bounds;
    try {
      bounds = _mapController.camera.visibleBounds;
      _currentZoom = _mapController.camera.zoom;
    } catch (_) {
      return;
    }

    final boundsStr = [
      bounds.west.toStringAsFixed(5),
      bounds.south.toStringAsFixed(5),
      bounds.east.toStringAsFixed(5),
      bounds.north.toStringAsFixed(5),
    ].join(',');

    _currentBoundsStr = boundsStr;
    _reconnectMapStream();
  }

  void _reconnectMapStream() {
    if (_currentBoundsStr == null) return;
    final filter = ref.read(cityFilterProvider(widget.cityId));

    final queryParams = <String, String>{};
    if (filter.routes.isNotEmpty) {
      queryParams['filterRoutes'] = filter.routes.map((r) => r.id).join(',');
    }
    if (filter.models.isNotEmpty) {
      queryParams['filterModels'] = filter.models.join(',');
    }
    final query = queryParams.isNotEmpty
        ? '?${Uri(queryParameters: queryParams).query}'
        : '';

    final endpoint = filter.isActive
        ? 'mapFeatures/0/0,0,0,0/stream$query'
        : 'mapFeatures/${_currentZoom.toStringAsFixed(2)}/$_currentBoundsStr/stream$query';

    _mapStreamController?.dispose();
    _mapStreamController =
        SseSubscriptionController<MapRealtimePayload, MapInitialPayload>(
          city: widget.cityId,
          endpoint: endpoint,
          parseInitial: (decoded) {
            if (decoded is! Map<String, dynamic>) {
              return const MapInitialPayload(stops: []);
            }
            final rawStops = decoded['stops'];
            return MapInitialPayload(
              stops: rawStops is List
                  ? rawStops
                        .whereType<List<dynamic>>()
                        .map(TransitStop.fromTuple)
                        .toList()
                  : const [],
              suggestedCity: decoded['suggestedCity']?.toString(),
            );
          },
          parseData: (decoded) {
            if (decoded is! Map<String, dynamic>) {
              return const MapRealtimePayload(vehicles: [], dots: []);
            }
            final rawPositions = decoded['positions'];
            final rawDots = decoded['dots'];
            return MapRealtimePayload(
              vehicles: rawPositions is List
                  ? rawPositions
                        .whereType<List<dynamic>>()
                        .map(VehiclePosition.fromTuple)
                        .toList()
                  : const [],
              dots: rawDots is List
                  ? rawDots
                        .whereType<List<dynamic>>()
                        .map(DotVehicle.fromTuple)
                        .toList()
                  : const [],
            );
          },
          onSnapshot: (next) {
            if (mounted) {
              setState(() => _mapSnapshot = next);
            }
          },
        )..start();
  }

  Future<void> _locateUser() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final target = LatLng(pos.latitude, pos.longitude);
      setState(() => _userLocation = target);
      _mapController.move(target, 15.0);
      _updateMapStreamFromBounds();
    } catch (_) {}
  }

  @override
  void dispose() {
    _cameraDebounce?.cancel();
    _mapStreamController?.dispose();
    super.dispose();
  }

  Widget? _buildBottomOverlay() {
    final effectiveApiCity =
        (widget.queryCity != null && widget.queryCity!.isNotEmpty)
        ? widget.queryCity!
        : widget.cityId;

    switch (widget.overlayKind) {
      case CityOverlayKind.none:
        return null;
      case CityOverlayKind.stop:
      case CityOverlayKind.station:
        if (widget.entityId == null) return null;
        return StopDeparturesSheet(
          city: effectiveApiCity,
          stopId: widget.entityId!,
          isStation: widget.overlayKind == CityOverlayKind.station,
        );
      case CityOverlayKind.vehicle:
        if (widget.entityId == null) return null;
        return TripSheet(
          routeCity: widget.cityId,
          apiCity: effectiveApiCity,
          vehicleId: widget.entityId,
          onShapeUpdated: (points) {
            if (mounted) {
              setState(() => _activeTripPolyline = points);
            }
          },
        );
      case CityOverlayKind.trip:
        if (widget.entityId == null) return null;
        return TripSheet(
          routeCity: widget.cityId,
          apiCity: effectiveApiCity,
          tripId: widget.entityId,
          onShapeUpdated: (points) {
            if (mounted) {
              setState(() => _activeTripPolyline = points);
            }
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final strings = AppStrings(settings.languageCode);
    final filterState = ref.watch(cityFilterProvider(widget.cityId));

    ref.listen<CityFilterState>(cityFilterProvider(widget.cityId), (_, _) {
      _reconnectMapStream();
    });

    final stops = _mapSnapshot.initialData?.stops ?? const [];
    final vehicles = _mapSnapshot.data?.vehicles ?? const [];
    final dots = _mapSnapshot.data?.dots ?? const [];
    final useDots = _mapSnapshot.data?.useDots ?? false;
    final bottomOverlay = _buildBottomOverlay();

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: City.defaultLocation,
              initialZoom: 16.0,
              minZoom: 5.0,
              maxZoom: 19.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onMapReady: () {
                _mapReady = true;
                _initializeCityCamera();
              },
              onPositionChanged: (camera, hasGesture) {
                if (!hasGesture) return;
                _cameraDebounce?.cancel();
                _cameraDebounce = Timer(const Duration(milliseconds: 350), () {
                  if (!mounted) return;
                  ref
                      .read(appSettingsProvider.notifier)
                      .saveMapPosition(camera.center, camera.zoom);
                  _updateMapStreamFromBounds();
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'live.zbiorkom.mobile',
              ),
              if (_activeTripPolyline.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _activeTripPolyline,
                      strokeWidth: 4.5,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              if (_currentZoom >= 14.0 && stops.isNotEmpty)
                MarkerLayer(
                  markers: stops.take(250).map((stop) {
                    return Marker(
                      point: stop.location,
                      width: 24,
                      height: 24,
                      child: GestureDetector(
                        onTap: () {
                          final suffix = TransitTools.buildCitySuffix(
                            stop.city,
                            widget.cityId,
                          );
                          context.go(
                            '/${widget.cityId}/stop/${Uri.encodeComponent(stop.id)}$suffix',
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          child: const Icon(Icons.directions_bus, size: 12),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              if (useDots)
                MarkerLayer(
                  markers: dots.map((dot) {
                    return Marker(
                      point: dot.location,
                      width: 14,
                      height: 14,
                      child: GestureDetector(
                        onTap: () {
                          _mapController.move(
                            dot.location,
                            _currentZoom < 15.0 ? 15.5 : _currentZoom + 1.5,
                          );
                          _updateMapStreamFromBounds();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: TransitTools.parseHexColor(dot.routeColor),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 1.5,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black38,
                                blurRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                )
              else
                MarkerLayer(
                  markers: vehicles.map((vehicle) {
                    final color = TransitTools.parseHexColor(
                      vehicle.route.color,
                    );
                    final badgeParts = <String>[vehicle.route.name];
                    if (settings.showBrigadeOnMarker &&
                        vehicle.brigade.isNotEmpty) {
                      badgeParts.add('/${vehicle.brigade}');
                    }
                    if (settings.showFleetOnMarker &&
                        vehicle.fleetNumber.isNotEmpty) {
                      badgeParts.add(' #${vehicle.fleetNumber}');
                    }

                    return Marker(
                      key: ValueKey(vehicle.id),
                      point: vehicle.location,
                      width: 78,
                      height: 30,
                      child: GestureDetector(
                        onTap: () {
                          final suffix = TransitTools.buildCitySuffix(
                            vehicle.city,
                            widget.cityId,
                          );
                          context.go(
                            '/${widget.cityId}/vehicle/${Uri.encodeComponent(vehicle.id)}$suffix',
                          );
                        },
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.2,
                              ),
                            ),
                            child: Text(
                              badgeParts.join(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              if (_userLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _userLocation!,
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'fab_search',
                      tooltip: strings.search,
                      onPressed: () =>
                          context.push('/${widget.cityId}/search'),
                      child: const Icon(Icons.search),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton.small(
                      heroTag: 'fab_favorites',
                      tooltip: strings.favoriteStops,
                      onPressed: () =>
                          context.push('/${widget.cityId}/favoriteStops'),
                      child: const Icon(Icons.star_border),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton.small(
                      heroTag: 'fab_filter',
                      tooltip: strings.filter,
                      backgroundColor: filterState.isActive
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      foregroundColor: filterState.isActive
                          ? Theme.of(context).colorScheme.onPrimary
                          : null,
                      onPressed: () =>
                          context.push('/${widget.cityId}/filter'),
                      child: const Icon(Icons.filter_alt_outlined),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton.small(
                      heroTag: 'fab_gps',
                      onPressed: _locateUser,
                      child: const Icon(Icons.my_location),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            bottom: bottomOverlay != null ? 330 : 12,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  strings.mapAttribution,
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ),
            ),
          ),
          if (bottomOverlay != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 320,
                width: double.infinity,
                child: Material(
                  elevation: 8,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: bottomOverlay,
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/${widget.cityId}');
            case 1:
              context.push('/${widget.cityId}/routes');
            case 2:
              context.push('/${widget.cityId}/favoriteStops');
            case 3:
              context.push('/${widget.cityId}/settings');
          }
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.map_outlined),
            selectedIcon: const Icon(Icons.map),
            label: strings.map,
          ),
          NavigationDestination(
            icon: const Icon(Icons.schedule_outlined),
            selectedIcon: const Icon(Icons.schedule),
            label: strings.schedules,
          ),
          NavigationDestination(
            icon: const Icon(Icons.star_outline),
            selectedIcon: const Icon(Icons.star),
            label: strings.favoriteStops,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: strings.settings,
          ),
        ],
      ),
    );
  }
}
