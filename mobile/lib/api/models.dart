import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

enum VehicleType {
  tram(0),
  subway(1),
  train(2),
  bus(3),
  ferry(4),
  aerialLift(6),
  funicular(7),
  trolleybus(11),
  monorail(12);

  const VehicleType(this.code);
  final int code;

  static VehicleType fromCode(int? code) {
    return VehicleType.values.firstWhere(
      (value) => value.code == code,
      orElse: () => VehicleType.bus,
    );
  }
}

enum StopDepartureStatus {
  scheduled(0),
  onTrip(1),
  onPreviousTrip(2),
  cancelled(3);

  const StopDepartureStatus(this.code);
  final int code;

  static StopDepartureStatus fromCode(int? code) {
    return StopDepartureStatus.values.firstWhere(
      (value) => value.code == code,
      orElse: () => StopDepartureStatus.scheduled,
    );
  }
}

@immutable
class CityAgency {
  const CityAgency({
    required this.id,
    required this.name,
    this.icon,
    this.faresUrl,
  });

  final String id;
  final String name;
  final String? icon;
  final String? faresUrl;

  factory CityAgency.fromJson(Map<String, dynamic> json, [String? fallbackId]) {
    return CityAgency(
      id: (json['id'] as String?) ?? fallbackId ?? '',
      name: (json['name'] as String?) ?? '',
      icon: json['icon'] as String?,
      faresUrl: json['faresUrl'] as String?,
    );
  }
}

@immutable
class City {
  const City({
    required this.id,
    required this.name,
    required this.location,
    required this.timezone,
    this.zoom = 16.0,
    this.description,
    this.showNewTag = false,
    this.disableBrigades = false,
    this.virtual = false,
    this.agencies = const {},
  });

  final String id;
  final String name;
  final LatLng location;
  final String timezone;
  final double zoom;
  final String? description;
  final bool showNewTag;
  final bool disableBrigades;
  final bool virtual;
  final Map<String, CityAgency> agencies;

  static const defaultTimezone = 'Europe/Warsaw';
  static const defaultLocation = LatLng(52.2297, 21.0122);

  factory City.fromJson(Map<String, dynamic> json) {
    final rawLoc = json['location'];
    var location = defaultLocation;
    if (rawLoc is List && rawLoc.length >= 2) {
      final lon = (rawLoc[0] as num?)?.toDouble();
      final lat = (rawLoc[1] as num?)?.toDouble();
      if (lat != null && lon != null) {
        location = LatLng(lat, lon);
      }
    }

    final agenciesMap = <String, CityAgency>{};
    final rawAgencies = json['agencies'];
    if (rawAgencies is Map) {
      rawAgencies.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          agenciesMap[key.toString()] = CityAgency.fromJson(
            value,
            key.toString(),
          );
        }
      });
    }

    return City(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      location: location,
      timezone: (json['timezone'] as String?)?.isNotEmpty == true
          ? json['timezone'] as String
          : defaultTimezone,
      zoom: (json['zoom'] as num?)?.toDouble() ?? 16.0,
      description: json['description'] as String?,
      showNewTag: json['showNewTag'] == true,
      disableBrigades: json['disableBrigades'] == true,
      virtual: json['virtual'] == true,
      agencies: agenciesMap,
    );
  }
}

@immutable
class TransitRoute {
  const TransitRoute({
    required this.id,
    required this.city,
    required this.name,
    required this.longName,
    required this.agency,
    required this.type,
    required this.color,
  });

  final String id;
  final String city;
  final String name;
  final String longName;
  final String agency;
  final VehicleType type;
  final String color;

  factory TransitRoute.fromTuple(List<dynamic> tuple) {
    return TransitRoute(
      id: tuple.isNotEmpty ? (tuple[0]?.toString() ?? '') : '',
      city: tuple.length > 1 ? (tuple[1]?.toString() ?? '') : '',
      name: tuple.length > 2 ? (tuple[2]?.toString() ?? '') : '',
      longName: tuple.length > 3 ? (tuple[3]?.toString() ?? '') : '',
      agency: tuple.length > 4 ? (tuple[4]?.toString() ?? '') : '',
      type: VehicleType.fromCode(
        tuple.length > 5 ? (tuple[5] as num?)?.toInt() : null,
      ),
      color: tuple.length > 6 && tuple[6] != null
          ? tuple[6].toString()
          : '#276b2b',
    );
  }

  List<dynamic> toTuple() => [
    id,
    city,
    name,
    longName,
    agency,
    type.code,
    color,
  ];
}

@immutable
class VehiclePosition {
  const VehiclePosition({
    required this.id,
    required this.city,
    required this.route,
    required this.brigade,
    required this.location,
    required this.bearing,
    required this.lastPing,
    required this.tripId,
    required this.percentTraveled,
  });

  final String id;
  final String city;
  final TransitRoute route;
  final String brigade;
  final LatLng location;
  final double bearing;
  final int lastPing;
  final String tripId;
  final double percentTraveled;

  String get fleetNumber {
    final colonIdx = id.indexOf(':');
    if (colonIdx == -1) return id;
    final underscoreIdx = id.indexOf('_', colonIdx + 1);
    if (underscoreIdx == -1 || underscoreIdx == colonIdx + 1) {
      return id.substring(colonIdx + 1);
    }
    return id.substring(underscoreIdx + 1);
  }

  factory VehiclePosition.fromTuple(List<dynamic> tuple) {
    final rawLoc = tuple.length > 4 && tuple[4] is List
        ? tuple[4] as List
        : const [];
    final lon = rawLoc.isNotEmpty ? (rawLoc[0] as num?)?.toDouble() ?? 0.0 : 0.0;
    final lat = rawLoc.length > 1 ? (rawLoc[1] as num?)?.toDouble() ?? 0.0 : 0.0;

    return VehiclePosition(
      id: tuple.isNotEmpty ? (tuple[0]?.toString() ?? '') : '',
      city: tuple.length > 1 ? (tuple[1]?.toString() ?? '') : '',
      route: tuple.length > 2 && tuple[2] is List
          ? TransitRoute.fromTuple(tuple[2] as List<dynamic>)
          : const TransitRoute(
              id: '',
              city: '',
              name: '?',
              longName: '',
              agency: '',
              type: VehicleType.bus,
              color: '#276b2b',
            ),
      brigade: tuple.length > 3 ? (tuple[3]?.toString() ?? '') : '',
      location: LatLng(lat, lon),
      bearing: tuple.length > 5 ? (tuple[5] as num?)?.toDouble() ?? 0.0 : 0.0,
      lastPing: tuple.length > 6 ? (tuple[6] as num?)?.toInt() ?? 0 : 0,
      tripId: tuple.length > 7 ? (tuple[7]?.toString() ?? '') : '',
      percentTraveled:
          tuple.length > 8 ? (tuple[8] as num?)?.toDouble() ?? 0.0 : 0.0,
    );
  }
}

@immutable
class DotVehicle {
  const DotVehicle({
    required this.routeColor,
    required this.location,
  });

  final String routeColor;
  final LatLng location;

  factory DotVehicle.fromTuple(List<dynamic> tuple) {
    final rawLoc = tuple.length > 1 && tuple[1] is List
        ? tuple[1] as List
        : const [];
    final lon = rawLoc.isNotEmpty ? (rawLoc[0] as num?)?.toDouble() ?? 0.0 : 0.0;
    final lat = rawLoc.length > 1 ? (rawLoc[1] as num?)?.toDouble() ?? 0.0 : 0.0;
    return DotVehicle(
      routeColor: tuple.isNotEmpty ? (tuple[0]?.toString() ?? '#276b2b') : '#276b2b',
      location: LatLng(lat, lon),
    );
  }
}

@immutable
class TransitStop {
  const TransitStop({
    required this.id,
    required this.city,
    required this.name,
    required this.code,
    required this.location,
    required this.types,
    required this.bearing,
    required this.direction,
    required this.routes,
  });

  final String id;
  final String city;
  final String name;
  final String code;
  final LatLng location;
  final List<VehicleType> types;
  final double bearing;
  final String direction;
  final List<TransitRoute> routes;

  factory TransitStop.fromTuple(List<dynamic> tuple) {
    final rawLoc = tuple.length > 4 && tuple[4] is List
        ? tuple[4] as List
        : const [];
    final lon = rawLoc.isNotEmpty ? (rawLoc[0] as num?)?.toDouble() ?? 0.0 : 0.0;
    final lat = rawLoc.length > 1 ? (rawLoc[1] as num?)?.toDouble() ?? 0.0 : 0.0;

    final rawTypes = tuple.length > 5 && tuple[5] is List
        ? tuple[5] as List
        : const [];
    final rawRoutes = tuple.length > 8 && tuple[8] is List
        ? tuple[8] as List
        : const [];

    return TransitStop(
      id: tuple.isNotEmpty ? (tuple[0]?.toString() ?? '') : '',
      city: tuple.length > 1 ? (tuple[1]?.toString() ?? '') : '',
      name: tuple.length > 2 ? (tuple[2]?.toString() ?? '') : '',
      code: tuple.length > 3 ? (tuple[3]?.toString() ?? '') : '',
      location: LatLng(lat, lon),
      types: rawTypes
          .map((item) => VehicleType.fromCode((item as num?)?.toInt()))
          .toList(),
      bearing: tuple.length > 6 ? (tuple[6] as num?)?.toDouble() ?? 0.0 : 0.0,
      direction: tuple.length > 7 ? (tuple[7]?.toString() ?? '') : '',
      routes: rawRoutes
          .whereType<List<dynamic>>()
          .map(TransitRoute.fromTuple)
          .toList(),
    );
  }
}

@immutable
class StopTimeInfo {
  const StopTimeInfo({
    required this.scheduled,
    required this.delayMs,
    required this.status,
    this.platform,
  });

  final int scheduled;
  final int? delayMs;
  final StopDepartureStatus status;
  final String? platform;

  int get estimatedEpochMs => scheduled + (delayMs ?? 0);

  factory StopTimeInfo.fromTuple(List<dynamic> tuple) {
    return StopTimeInfo(
      scheduled: tuple.isNotEmpty ? (tuple[0] as num?)?.toInt() ?? 0 : 0,
      delayMs: tuple.length > 1 && tuple[1] is num
          ? (tuple[1] as num).toInt()
          : null,
      status: StopDepartureStatus.fromCode(
        tuple.length > 2 ? (tuple[2] as num?)?.toInt() : null,
      ),
      platform: tuple.length > 3 && tuple[3] != null
          ? tuple[3].toString()
          : null,
    );
  }
}

@immutable
class TripDetails {
  const TripDetails({
    required this.id,
    required this.city,
    required this.route,
    required this.headsign,
    required this.brigade,
    required this.shortName,
    required this.description,
    this.firstStopName,
    this.firstStopArrival,
    this.lastStopName,
    this.lastStopDeparture,
    this.distance,
  });

  final String id;
  final String city;
  final TransitRoute route;
  final String headsign;
  final String brigade;
  final String shortName;
  final List<MapEntry<String, String>> description;
  final String? firstStopName;
  final int? firstStopArrival;
  final String? lastStopName;
  final int? lastStopDeparture;
  final double? distance;

  factory TripDetails.fromTuple(List<dynamic> tuple) {
    final desc = <MapEntry<String, String>>[];
    if (tuple.length > 6 && tuple[6] is List) {
      for (final entry in tuple[6] as List) {
        if (entry is List && entry.length >= 2) {
          desc.add(
            MapEntry(entry[0]?.toString() ?? '', entry[1]?.toString() ?? ''),
          );
        }
      }
    }

    String? firstName;
    int? firstArrival;
    if (tuple.length > 7 && tuple[7] is List && (tuple[7] as List).length >= 2) {
      final first = tuple[7] as List;
      firstName = first[0]?.toString();
      firstArrival = (first[1] as num?)?.toInt();
    }

    String? lastName;
    int? lastDep;
    if (tuple.length > 8 && tuple[8] is List && (tuple[8] as List).length >= 2) {
      final last = tuple[8] as List;
      lastName = last[0]?.toString();
      lastDep = (last[1] as num?)?.toInt();
    }

    return TripDetails(
      id: tuple.isNotEmpty ? (tuple[0]?.toString() ?? '') : '',
      city: tuple.length > 1 ? (tuple[1]?.toString() ?? '') : '',
      route: tuple.length > 2 && tuple[2] is List
          ? TransitRoute.fromTuple(tuple[2] as List<dynamic>)
          : const TransitRoute(
              id: '',
              city: '',
              name: '?',
              longName: '',
              agency: '',
              type: VehicleType.bus,
              color: '#276b2b',
            ),
      headsign: tuple.length > 3 ? (tuple[3]?.toString() ?? '') : '',
      brigade: tuple.length > 4 ? (tuple[4]?.toString() ?? '') : '',
      shortName: tuple.length > 5 ? (tuple[5]?.toString() ?? '') : '',
      description: desc,
      firstStopName: firstName,
      firstStopArrival: firstArrival,
      lastStopName: lastName,
      lastStopDeparture: lastDep,
      distance: tuple.length > 9 ? (tuple[9] as num?)?.toDouble() : null,
    );
  }
}

@immutable
class StopDeparture {
  const StopDeparture({
    required this.trip,
    required this.vehicle,
    required this.departure,
    this.destination,
  });

  final TripDetails trip;
  final VehiclePosition? vehicle;
  final StopTimeInfo departure;
  final StopTimeInfo? destination;

  factory StopDeparture.fromTuple(List<dynamic> tuple) {
    return StopDeparture(
      trip: tuple.isNotEmpty && tuple[0] is List
          ? TripDetails.fromTuple(tuple[0] as List<dynamic>)
          : TripDetails.fromTuple(const []),
      vehicle: tuple.length > 1 && tuple[1] is List
          ? VehiclePosition.fromTuple(tuple[1] as List<dynamic>)
          : null,
      departure: tuple.length > 2 && tuple[2] is List
          ? StopTimeInfo.fromTuple(tuple[2] as List<dynamic>)
          : const StopTimeInfo(
              scheduled: 0,
              delayMs: null,
              status: StopDepartureStatus.scheduled,
            ),
      destination: tuple.length > 3 && tuple[3] is List
          ? StopTimeInfo.fromTuple(tuple[3] as List<dynamic>)
          : null,
    );
  }
}

@immutable
class ItineraryStopEntry {
  const ItineraryStopEntry({
    required this.stop,
    required this.alightFlags,
    required this.distance,
    this.platform,
  });

  final TransitStop stop;
  final int alightFlags;
  final double distance;
  final String? platform;

  bool get isOnDemand => (alightFlags & (1 << 2)) != 0;
  bool get isLastStop => (alightFlags & (1 << 3)) != 0;

  factory ItineraryStopEntry.fromTuple(List<dynamic> tuple) {
    return ItineraryStopEntry(
      stop: tuple.isNotEmpty && tuple[0] is List
          ? TransitStop.fromTuple(tuple[0] as List<dynamic>)
          : TransitStop.fromTuple(const []),
      alightFlags: tuple.length > 1 ? (tuple[1] as num?)?.toInt() ?? 0 : 0,
      distance: tuple.length > 2 ? (tuple[2] as num?)?.toDouble() ?? 0.0 : 0.0,
      platform: tuple.length > 3 && tuple[3] != null
          ? tuple[3].toString()
          : null,
    );
  }
}

@immutable
class TripStopUpdate {
  const TripStopUpdate({
    required this.arrival,
    required this.departure,
  });

  final StopTimeInfo arrival;
  final StopTimeInfo departure;

  factory TripStopUpdate.fromTuple(List<dynamic> tuple) {
    return TripStopUpdate(
      arrival: tuple.isNotEmpty && tuple[0] is List
          ? StopTimeInfo.fromTuple(tuple[0] as List<dynamic>)
          : const StopTimeInfo(
              scheduled: 0,
              delayMs: null,
              status: StopDepartureStatus.scheduled,
            ),
      departure: tuple.length > 1 && tuple[1] is List
          ? StopTimeInfo.fromTuple(tuple[1] as List<dynamic>)
          : const StopTimeInfo(
              scheduled: 0,
              delayMs: null,
              status: StopDepartureStatus.scheduled,
            ),
    );
  }
}

@immutable
class TransitAlert {
  const TransitAlert({
    required this.title,
    required this.description,
    required this.url,
    this.publishedAt,
    this.activeFrom,
    this.activeUntil,
  });

  final String title;
  final String description;
  final String url;
  final int? publishedAt;
  final int? activeFrom;
  final int? activeUntil;

  factory TransitAlert.fromTuple(List<dynamic> tuple) {
    return TransitAlert(
      title: tuple.isNotEmpty ? (tuple[0]?.toString() ?? '') : '',
      description: tuple.length > 1 ? (tuple[1]?.toString() ?? '') : '',
      url: tuple.length > 2 ? (tuple[2]?.toString() ?? '') : '',
      publishedAt: tuple.length > 3 ? (tuple[3] as num?)?.toInt() : null,
      activeFrom: tuple.length > 4 ? (tuple[4] as num?)?.toInt() : null,
      activeUntil: tuple.length > 5 ? (tuple[5] as num?)?.toInt() : null,
    );
  }
}

@immutable
class VehicleInfoDetails {
  const VehicleInfoDetails({
    required this.id,
    required this.model,
    required this.prodYear,
    required this.carrier,
    this.imageHash,
  });

  final String id;
  final String model;
  final int? prodYear;
  final String carrier;
  final String? imageHash;

  factory VehicleInfoDetails.fromTuple(List<dynamic> tuple) {
    return VehicleInfoDetails(
      id: tuple.isNotEmpty ? (tuple[0]?.toString() ?? '') : '',
      model: tuple.length > 1 ? (tuple[1]?.toString() ?? '') : '',
      prodYear: tuple.length > 2 ? (tuple[2] as num?)?.toInt() : null,
      carrier: tuple.length > 3 ? (tuple[3]?.toString() ?? '') : '',
      imageHash: tuple.length > 4 ? tuple[4]?.toString() : null,
    );
  }
}

@immutable
class SearchVehicleItem {
  const SearchVehicleItem({
    required this.id,
    required this.route,
    required this.brigade,
    this.headsign,
    this.model,
  });

  final String id;
  final TransitRoute route;
  final String brigade;
  final String? headsign;
  final String? model;

  factory SearchVehicleItem.fromTuple(List<dynamic> tuple) {
    return SearchVehicleItem(
      id: tuple.isNotEmpty ? (tuple[0]?.toString() ?? '') : '',
      route: tuple.length > 1 && tuple[1] is List
          ? TransitRoute.fromTuple(tuple[1] as List<dynamic>)
          : TransitRoute.fromTuple(const []),
      brigade: tuple.length > 2 ? (tuple[2]?.toString() ?? '') : '',
      headsign: tuple.length > 3 ? tuple[3]?.toString() : null,
      model: tuple.length > 4 ? tuple[4]?.toString() : null,
    );
  }
}

@immutable
class SearchStopGroupItem {
  const SearchStopGroupItem({
    required this.id,
    required this.city,
    required this.name,
    required this.stops,
    required this.isStation,
  });

  final String id;
  final String city;
  final String name;
  final List<TransitStop> stops;
  final bool isStation;

  factory SearchStopGroupItem.fromTuple(
    List<dynamic> tuple, {
    required bool isStation,
  }) {
    final rawStops = tuple.length > 3 && tuple[3] is List
        ? tuple[3] as List
        : const [];
    return SearchStopGroupItem(
      id: tuple.isNotEmpty ? (tuple[0]?.toString() ?? '') : '',
      city: tuple.length > 1 ? (tuple[1]?.toString() ?? '') : '',
      name: tuple.length > 2 ? (tuple[2]?.toString() ?? '') : '',
      stops: rawStops
          .whereType<List<dynamic>>()
          .map(TransitStop.fromTuple)
          .toList(),
      isStation: isStation,
    );
  }
}

@immutable
class SearchRelationItem {
  const SearchRelationItem({
    required this.id,
    required this.route,
    required this.shortName,
    required this.startMs,
    required this.endMs,
    required this.headsign,
  });

  final String id;
  final TransitRoute route;
  final String shortName;
  final int startMs;
  final int endMs;
  final String headsign;

  factory SearchRelationItem.fromTuple(List<dynamic> tuple) {
    return SearchRelationItem(
      id: tuple.isNotEmpty ? (tuple[0]?.toString() ?? '') : '',
      route: tuple.length > 1 && tuple[1] is List
          ? TransitRoute.fromTuple(tuple[1] as List<dynamic>)
          : TransitRoute.fromTuple(const []),
      shortName: tuple.length > 2 ? (tuple[2]?.toString() ?? '') : '',
      startMs: tuple.length > 3 ? (tuple[3] as num?)?.toInt() ?? 0 : 0,
      endMs: tuple.length > 4 ? (tuple[4] as num?)?.toInt() ?? 0 : 0,
      headsign: tuple.length > 5 ? (tuple[5]?.toString() ?? '') : '',
    );
  }
}

@immutable
class SearchResultEntry {
  const SearchResultEntry({
    this.vehicle,
    this.stop,
    this.station,
    this.route,
    this.relation,
  });

  final SearchVehicleItem? vehicle;
  final SearchStopGroupItem? stop;
  final SearchStopGroupItem? station;
  final TransitRoute? route;
  final SearchRelationItem? relation;

  factory SearchResultEntry.fromJson(Map<String, dynamic> json) {
    return SearchResultEntry(
      vehicle: json['vehicle'] is List
          ? SearchVehicleItem.fromTuple(json['vehicle'] as List<dynamic>)
          : null,
      stop: json['stop'] is List
          ? SearchStopGroupItem.fromTuple(
              json['stop'] as List<dynamic>,
              isStation: false,
            )
          : null,
      station: json['station'] is List
          ? SearchStopGroupItem.fromTuple(
              json['station'] as List<dynamic>,
              isStation: true,
            )
          : null,
      route: json['route'] is List
          ? TransitRoute.fromTuple(json['route'] as List<dynamic>)
          : null,
      relation: json['relation'] is List
          ? SearchRelationItem.fromTuple(json['relation'] as List<dynamic>)
          : null,
    );
  }
}

@immutable
class SearchResultsBundle {
  const SearchResultsBundle({
    required this.results,
    required this.groups,
    required this.groupNames,
  });

  final List<SearchResultEntry> results;
  final List<int> groups;
  final List<String> groupNames;

  factory SearchResultsBundle.fromJson(Map<String, dynamic> json) {
    final rawResults = json['results'] is List ? json['results'] as List : const [];
    final rawGroups = json['groups'] is List ? json['groups'] as List : const [];
    final rawNames = json['groupNames'] is List
        ? json['groupNames'] as List
        : const [];

    return SearchResultsBundle(
      results: rawResults
          .whereType<Map<String, dynamic>>()
          .map(SearchResultEntry.fromJson)
          .toList(),
      groups: rawGroups.map((e) => (e as num?)?.toInt() ?? 0).toList(),
      groupNames: rawNames.map((e) => e.toString()).toList(),
    );
  }
}

@immutable
class FavoriteStopEntry {
  const FavoriteStopEntry({
    required this.id,
    required this.name,
    required this.code,
    required this.location,
    this.isStation = false,
  });

  final String id;
  final String name;
  final String code;
  final LatLng location;
  final bool isStation;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'code': code,
    'location': [location.longitude, location.latitude],
    'isStation': isStation,
  };

  factory FavoriteStopEntry.fromJson(Map<String, dynamic> json) {
    final loc = json['location'] is List ? json['location'] as List : const [0, 0];
    final lon = loc.isNotEmpty ? (loc[0] as num?)?.toDouble() ?? 0.0 : 0.0;
    final lat = loc.length > 1 ? (loc[1] as num?)?.toDouble() ?? 0.0 : 0.0;
    return FavoriteStopEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      location: LatLng(lat, lon),
      isStation: json['isStation'] == true,
    );
  }
}
