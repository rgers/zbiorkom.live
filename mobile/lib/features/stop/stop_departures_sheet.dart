import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../api/models.dart';
import '../../api/sse_client.dart';
import '../../core/transit_tools.dart';
import '../../l10n/app_strings.dart';
import '../../state/app_providers.dart';
import '../../widgets/route_badge.dart';

class StopDeparturesSheet extends ConsumerStatefulWidget {
  const StopDeparturesSheet({
    super.key,
    required this.city,
    required this.stopId,
    this.isStation = false,
  });

  final String city;
  final String stopId;
  final bool isStation;

  @override
  ConsumerState<StopDeparturesSheet> createState() =>
      _StopDeparturesSheetState();
}

class _StopDeparturesSheetState extends ConsumerState<StopDeparturesSheet> {
  SseSubscriptionController<List<StopDeparture>, TransitStop>? _controller;
  SseStreamSnapshot<List<StopDeparture>, TransitStop> _snapshot =
      const SseStreamSnapshot(isLoading: true);
  String? _selectedDestinationId;
  int _limit = 15;

  @override
  void initState() {
    super.initState();
    _startStream();
  }

  @override
  void didUpdateWidget(covariant StopDeparturesSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.city != widget.city || oldWidget.stopId != widget.stopId) {
      _selectedDestinationId = null;
      _limit = 15;
      _startStream();
    }
  }

  void _startStream() {
    _controller?.dispose();
    final queryParams = <String, String>{
      'limit': '${_limit + 1}',
      if (_selectedDestinationId != null && _selectedDestinationId!.isNotEmpty)
        'destinations': _selectedDestinationId!,
    };
    final query = Uri(queryParameters: queryParams).query;
    final endpoint =
        'stops/${Uri.encodeComponent(widget.stopId)}/stream?$query';

    _controller = SseSubscriptionController<List<StopDeparture>, TransitStop>(
      city: widget.city,
      endpoint: endpoint,
      parseInitial: (decoded) {
        if (decoded is List) {
          return TransitStop.fromTuple(decoded);
        }
        throw const FormatException('Invalid stop tuple');
      },
      parseData: (decoded) {
        if (decoded is! List) return const [];
        return decoded
            .whereType<List<dynamic>>()
            .map(StopDeparture.fromTuple)
            .toList();
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
    _controller?.dispose();
    super.dispose();
  }

  String _formatDelay(AppStrings strings, StopTimeInfo time) {
    if (time.status == StopDepartureStatus.cancelled) {
      return strings.cancelled;
    }
    final delay = TransitTools.classifyDelay(time.delayMs);
    switch (delay.classification) {
      case DelayClassification.onTime:
        return strings.onTime;
      case DelayClassification.delayed:
        return strings.delayed(delay.formattedDuration);
      case DelayClassification.early:
        return strings.early(delay.formattedDuration);
      case DelayClassification.unknown:
        return strings.scheduledOnly;
    }
  }

  Color _delayColor(StopTimeInfo time) {
    if (time.status == StopDepartureStatus.cancelled) {
      return Colors.redAccent;
    }
    final delay = TransitTools.classifyDelay(time.delayMs);
    switch (delay.classification) {
      case DelayClassification.onTime:
        return Colors.greenAccent;
      case DelayClassification.delayed:
        return Colors.orangeAccent;
      case DelayClassification.early:
        return Colors.lightBlueAccent;
      case DelayClassification.unknown:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final strings = AppStrings(settings.languageCode);
    final favorites = ref.watch(favoriteStopsProvider(widget.city));
    final isFav = favorites.any((s) => s.id == widget.stopId);

    final destinationsAsync = ref.watch(
      stopDestinationsProvider((city: widget.city, stopId: widget.stopId)),
    );

    final stop = _snapshot.initialData;
    final allDepartures = _snapshot.data ?? const [];
    final hasMore = allDepartures.length > _limit;
    final departures = hasMore
        ? allDepartures.take(_limit).toList()
        : allDepartures;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stop?.name ?? widget.stopId,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (stop != null &&
                          (stop.code.isNotEmpty || stop.direction.isNotEmpty))
                        Text(
                          [
                            if (stop.code.isNotEmpty) '#${stop.code}',
                            if (stop.direction.isNotEmpty) '→ ${stop.direction}',
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (stop != null)
                  IconButton(
                    tooltip: strings.favoriteStops,
                    icon: Icon(
                      isFav ? Icons.star : Icons.star_border,
                      color: isFav ? Colors.amber : null,
                    ),
                    onPressed: () {
                      ref
                          .read(favoriteStopsProvider(widget.city).notifier)
                          .toggleStop(
                            FavoriteStopEntry(
                              id: stop.id,
                              name: stop.name,
                              code: stop.code,
                              location: stop.location,
                              isStation: widget.isStation,
                            ),
                          );
                    },
                  ),
                IconButton(
                  tooltip: strings.share,
                  icon: const Icon(Icons.share),
                  onPressed: () {
                    final kind = widget.isStation ? 'station' : 'stop';
                    SharePlus.instance.share(
                      ShareParams(
                        text:
                            'https://zbiorkom.live/${widget.city}/$kind/${Uri.encodeComponent(widget.stopId)}',
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => context.go('/${widget.city}'),
                ),
              ],
            ),
          ),
          destinationsAsync.when(
            data: (destinations) {
              if (destinations.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(strings.anywhere),
                        selected: _selectedDestinationId == null,
                        onSelected: (_) {
                          setState(() => _selectedDestinationId = null);
                          _startStream();
                        },
                      ),
                    ),
                    ...destinations.map(
                      (dest) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(dest.name),
                          selected: _selectedDestinationId == dest.id,
                          onSelected: (selected) {
                            setState(
                              () => _selectedDestinationId = selected
                                  ? dest.id
                                  : null,
                            );
                            _startStream();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const Divider(height: 1),
          Expanded(
            child: _snapshot.isLoading && departures.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _snapshot.error != null && departures.isEmpty
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
                : departures.isEmpty
                ? Center(child: Text(strings.noDepartures))
                : ListView.separated(
                    itemCount: departures.length + (hasMore ? 1 : 0),
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (index == departures.length) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() => _limit += 15);
                              _startStream();
                            },
                            child: const Text('+15'),
                          ),
                        );
                      }
                      final dep = departures[index];
                      final estTime = TransitTools.formatTimeHHmm(
                        dep.departure.estimatedEpochMs,
                      );
                      final diffMinutes =
                          ((dep.departure.estimatedEpochMs -
                                      DateTime.now().millisecondsSinceEpoch) /
                                  60000)
                              .round();

                      return ListTile(
                        leading: RouteBadge(
                          route: dep.trip.route,
                          subtitle: dep.trip.brigade,
                        ),
                        title: Text(
                          dep.trip.headsign,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          [
                            _formatDelay(strings, dep.departure),
                            if (dep.vehicle != null)
                              '#${dep.vehicle!.fleetNumber}',
                            if (dep.departure.platform != null &&
                                dep.departure.platform!.isNotEmpty)
                              '${strings.platform} ${dep.departure.platform}',
                          ].join(' · '),
                          style: TextStyle(color: _delayColor(dep.departure)),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              diffMinutes >= 0 && diffMinutes <= 59
                                  ? '$diffMinutes min'
                                  : estTime,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              estTime,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        onTap: () {
                          if (dep.vehicle != null &&
                              dep.vehicle!.id.isNotEmpty) {
                            final suffix = TransitTools.buildCitySuffix(
                              dep.vehicle!.city,
                              widget.city,
                            );
                            context.go(
                              '/${widget.city}/vehicle/${Uri.encodeComponent(dep.vehicle!.id)}$suffix',
                            );
                          } else if (dep.trip.id.isNotEmpty) {
                            final suffix = TransitTools.buildCitySuffix(
                              dep.trip.city,
                              widget.city,
                            );
                            context.go(
                              '/${widget.city}/trip/${Uri.encodeComponent(dep.trip.id)}$suffix',
                            );
                          }
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
