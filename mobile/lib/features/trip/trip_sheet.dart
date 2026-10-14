import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import '../../api/models.dart';
import '../../api/sse_client.dart';
import '../../core/transit_tools.dart';
import '../../l10n/app_strings.dart';
import '../../state/app_providers.dart';
import '../../widgets/route_badge.dart';

class TripInitialPayload {
  const TripInitialPayload({
    required this.trip,
    required this.stops,
    required this.shapePoints,
  });

  final TripDetails trip;
  final List<ItineraryStopEntry> stops;
  final List<LatLng> shapePoints;
}

class TripRealtimePayload {
  const TripRealtimePayload({
    this.position,
    this.sequence,
    this.stopUpdates = const [],
    this.alerts = const [],
  });

  final VehiclePosition? position;
  final int? sequence;
  final List<TripStopUpdate> stopUpdates;
  final List<TransitAlert> alerts;
}

class TripSheet extends ConsumerStatefulWidget {
  const TripSheet({
    super.key,
    required this.routeCity,
    required this.apiCity,
    this.tripId,
    this.vehicleId,
    this.onShapeUpdated,
  });

  final String routeCity;
  final String apiCity;
  final String? tripId;
  final String? vehicleId;
  final ValueChanged<List<LatLng>>? onShapeUpdated;

  @override
  ConsumerState<TripSheet> createState() => _TripSheetState();
}

class _TripSheetState extends ConsumerState<TripSheet> {
  SseSubscriptionController<TripRealtimePayload, TripInitialPayload>?
  _controller;
  SseStreamSnapshot<TripRealtimePayload, TripInitialPayload> _snapshot =
      const SseStreamSnapshot(isLoading: true);

  @override
  void initState() {
    super.initState();
    _startStream();
  }

  @override
  void didUpdateWidget(covariant TripSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiCity != widget.apiCity ||
        oldWidget.tripId != widget.tripId ||
        oldWidget.vehicleId != widget.vehicleId) {
      _startStream();
    }
  }

  void _startStream() {
    _controller?.dispose();
    final endpoint = widget.tripId != null
        ? 'trips/${Uri.encodeComponent(widget.tripId!)}/stream'
        : widget.vehicleId != null
        ? 'positions/${Uri.encodeComponent(widget.vehicleId!)}/stream'
        : '';

    _controller =
        SseSubscriptionController<TripRealtimePayload, TripInitialPayload>(
          city: widget.apiCity,
          endpoint: endpoint,
          parseInitial: (decoded) {
            if (decoded is! Map<String, dynamic>) {
              throw const FormatException('Invalid trip initial payload');
            }
            final tripRaw = decoded['trip'];
            final itineraryRaw = decoded['itinerary'];
            final trip = tripRaw is List
                ? TripDetails.fromTuple(tripRaw)
                : TripDetails.fromTuple(const []);

            var stops = <ItineraryStopEntry>[];
            var shapePoints = <LatLng>[];
            if (itineraryRaw is List && itineraryRaw.isNotEmpty) {
              if (itineraryRaw[0] is List) {
                stops = (itineraryRaw[0] as List)
                    .whereType<List<dynamic>>()
                    .map(ItineraryStopEntry.fromTuple)
                    .toList();
              }
              if (itineraryRaw.length > 1 && itineraryRaw[1] is String) {
                shapePoints = TransitTools.decodePolyline6(
                  itineraryRaw[1] as String,
                );
              }
            }
            widget.onShapeUpdated?.call(shapePoints);
            return TripInitialPayload(
              trip: trip,
              stops: stops,
              shapePoints: shapePoints,
            );
          },
          parseData: (decoded) {
            if (decoded is! Map<String, dynamic>) {
              return const TripRealtimePayload();
            }
            final posRaw = decoded['position'];
            final stopsRaw = decoded['stops'];
            final alertsRaw = decoded['alerts'];
            return TripRealtimePayload(
              position: posRaw is List
                  ? VehiclePosition.fromTuple(posRaw)
                  : null,
              sequence: (decoded['sequence'] as num?)?.toInt(),
              stopUpdates: stopsRaw is List
                  ? stopsRaw
                        .whereType<List<dynamic>>()
                        .map(TripStopUpdate.fromTuple)
                        .toList()
                  : const [],
              alerts: alertsRaw is List
                  ? alertsRaw
                        .whereType<List<dynamic>>()
                        .map(TransitAlert.fromTuple)
                        .toList()
                  : const [],
            );
          },
          onSnapshot: (next) {
            if (mounted) {
              setState(() => _snapshot = next);
            }
          },
        )..start();
  }

  @override
  void dispose() {
    widget.onShapeUpdated?.call(const []);
    _controller?.dispose();
    super.dispose();
  }

  void _showVehicleInfoDialog(BuildContext context, String vehicleId) {
    final settings = ref.read(appSettingsProvider);
    final strings = AppStrings(settings.languageCode);

    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final infoAsync = ref.watch(
              vehicleInfoProvider((city: widget.apiCity, vehicleId: vehicleId)),
            );
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: infoAsync.when(
                  data: (info) {
                    if (info == null) {
                      return Text(strings.noVehicleData);
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${strings.vehicleInfo} · #${info.id}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        if (info.model.isNotEmpty)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.directions_bus),
                            title: Text(strings.model),
                            subtitle: Text(info.model),
                          ),
                        if (info.carrier.isNotEmpty)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.business),
                            title: Text(strings.carrier),
                            subtitle: Text(info.carrier),
                          ),
                        if (info.prodYear != null && info.prodYear! > 0)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.calendar_today),
                            title: Text(strings.prodYear),
                            subtitle: Text('${info.prodYear}'),
                          ),
                      ],
                    );
                  },
                  loading: () => const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => Text(strings.noVehicleData),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final strings = AppStrings(settings.languageCode);

    final initial = _snapshot.initialData;
    final live = _snapshot.data;
    final trip = initial?.trip;
    final vehicle = live?.position;
    final effectiveVehicleId = vehicle?.id ?? widget.vehicleId;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                if (trip != null)
                  RouteBadge(route: trip.route, subtitle: trip.brigade)
                else if (vehicle != null)
                  RouteBadge(route: vehicle.route, subtitle: vehicle.brigade),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip?.headsign ?? effectiveVehicleId ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (vehicle != null)
                        Text(
                          '#${vehicle.fleetNumber}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (effectiveVehicleId != null && effectiveVehicleId.isNotEmpty)
                  IconButton(
                    tooltip: strings.vehicleInfo,
                    icon: const Icon(Icons.info_outline),
                    onPressed: () =>
                        _showVehicleInfoDialog(context, effectiveVehicleId),
                  ),
                IconButton(
                  tooltip: strings.share,
                  icon: const Icon(Icons.share),
                  onPressed: () {
                    final path = widget.vehicleId != null
                        ? 'vehicle/${Uri.encodeComponent(widget.vehicleId!)}'
                        : 'trip/${Uri.encodeComponent(widget.tripId ?? '')}';
                    SharePlus.instance.share(
                      ShareParams(
                        text: 'https://zbiorkom.live/${widget.routeCity}/$path',
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => context.go('/${widget.routeCity}'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _snapshot.isLoading && initial == null
                ? const Center(child: CircularProgressIndicator())
                : _snapshot.error != null && initial == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(strings.serverError),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _startStream,
                          child: Text(strings.retry),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: initial?.stops.length ?? 0,
                    itemBuilder: (context, index) {
                      final entry = initial!.stops[index];
                      final stopUpdate =
                          live != null && index < live.stopUpdates.length
                          ? live.stopUpdates[index]
                          : null;
                      final passed =
                          live?.sequence != null && index < live!.sequence!;
                      final isCurrent = live?.sequence == index;

                      final timeInfo = stopUpdate?.departure ??
                          stopUpdate?.arrival;
                      final timeText = timeInfo != null
                          ? TransitTools.formatTimeHHmm(
                              timeInfo.estimatedEpochMs,
                            )
                          : '--:--';

                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isCurrent
                              ? Icons.radio_button_checked
                              : passed
                              ? Icons.check_circle_outline
                              : Icons.circle_outlined,
                          size: 18,
                          color: isCurrent
                              ? Theme.of(context).colorScheme.primary
                              : passed
                              ? Colors.grey
                              : null,
                        ),
                        title: Text(
                          entry.stop.name,
                          style: TextStyle(
                            fontWeight: isCurrent
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: passed ? Colors.grey : null,
                          ),
                        ),
                        subtitle: entry.isOnDemand
                            ? const Text('NŻ / On demand')
                            : null,
                        trailing: Text(
                          timeText,
                          style: TextStyle(
                            fontWeight: isCurrent
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: passed ? Colors.grey : null,
                          ),
                        ),
                        onTap: () {
                          final suffix = TransitTools.buildCitySuffix(
                            entry.stop.city,
                            widget.routeCity,
                          );
                          context.go(
                            '/${widget.routeCity}/stop/${Uri.encodeComponent(entry.stop.id)}$suffix',
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
