import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zbiorkom_mobile/api/api_client.dart';
import 'package:zbiorkom_mobile/api/models.dart';
import 'package:zbiorkom_mobile/api/sse_client.dart';
import 'package:zbiorkom_mobile/core/transit_tools.dart';
import 'package:zbiorkom_mobile/main.dart';
import 'package:zbiorkom_mobile/state/app_providers.dart';

class FakeZbiorkomApiClient extends ZbiorkomApiClient {
  FakeZbiorkomApiClient(this.citiesToReturn);

  final List<City> citiesToReturn;

  @override
  Future<List<City>> loadCities() async {
    return citiesToReturn;
  }
}

void main() {
  group('Tuple & domain model parsers', () {
    test('parses TransitRoute and VehiclePosition tuples', () {
      final routeTuple = [
        'r_105',
        'warsaw',
        '105',
        'Os. Górczewska - Rondo Daszyńskiego',
        'ZTM',
        3,
        '#d32f2f',
      ];
      final vehicleTuple = [
        'bus:wtp_5869',
        'warsaw',
        routeTuple,
        '1',
        [21.0122, 52.2297],
        90.0,
        1720000000000,
        'trip_1',
        42.5,
      ];

      final vehicle = VehiclePosition.fromTuple(vehicleTuple);
      expect(vehicle.id, 'bus:wtp_5869');
      expect(vehicle.fleetNumber, '5869');
      expect(vehicle.route.name, '105');
      expect(vehicle.route.type, VehicleType.bus);
      expect(vehicle.brigade, '1');
      expect(vehicle.location.latitude, closeTo(52.2297, 0.0001));
      expect(vehicle.location.longitude, closeTo(21.0122, 0.0001));
      expect(vehicle.percentTraveled, 42.5);
    });

    test('parses StopDeparture tuple with delay and platform', () {
      final routeTuple = ['r_1', 'warsaw', '1', 'Annopol - Banacha', 'TW', 0, '#f57c00'];
      final tripTuple = [
        't_1',
        'warsaw',
        routeTuple,
        'Banacha',
        '04',
        '1',
        [
          ['info', 'Low floor'],
        ],
        ['Annopol', 1720000000000],
        ['Banacha', 1720003600000],
        12500,
      ];
      final departureTuple = [
        tripTuple,
        null,
        [1720000500000, 120000, 1, '2A'],
      ];

      final dep = StopDeparture.fromTuple(departureTuple);
      expect(dep.trip.headsign, 'Banacha');
      expect(dep.trip.route.type, VehicleType.tram);
      expect(dep.departure.delayMs, 120000);
      expect(dep.departure.status, StopDepartureStatus.onTrip);
      expect(dep.departure.platform, '2A');
      expect(dep.departure.estimatedEpochMs, 1720000620000);
    });
  });

  group('TransitTools utilities', () {
    test('normalizes Polish diacritics for search', () {
      expect(
        TransitTools.normalizeSearch('Górczewska Łódź Świętokrzyska'),
        'gorczewska lodz swietokrzyska',
      );
    });

    test('computes daysSince2020 consistently', () {
      expect(TransitTools.getDaysSince2020(DateTime.utc(2020, 1, 1)), 0);
      expect(TransitTools.getDaysSince2020(DateTime.utc(2020, 1, 11)), 10);
    });

    test('classifies delays accurately', () {
      final delayed = TransitTools.classifyDelay(180000);
      expect(delayed.classification, DelayClassification.delayed);
      expect(delayed.formattedDuration, '3 min');

      final early = TransitTools.classifyDelay(-60000);
      expect(early.classification, DelayClassification.early);
      expect(early.formattedDuration, '1 min');

      final onTime = TransitTools.classifyDelay(15000);
      expect(onTime.classification, DelayClassification.onTime);
    });
  });

  group('SSE parser', () {
    test('parses initial and message frames', () {
      final parser = SseParser();
      expect(parser.feedLine('event: initial'), isNull);
      expect(parser.feedLine('data: {"stops":[]}'), isNull);
      final frame1 = parser.feedLine('');
      expect(frame1, isNotNull);
      expect(frame1!.event, 'initial');
      expect(frame1.data, '{"stops":[]}');

      expect(parser.feedLine('data: {"positions":[]}'), isNull);
      final frame2 = parser.feedLine('');
      expect(frame2, isNotNull);
      expect(frame2!.event, 'message');
      expect(frame2.data, '{"positions":[]}');
    });
  });

  testWidgets('boots into city picker when no city is saved', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final fakeCities = [
      const City(
        id: 'warsaw',
        name: 'Warszawa',
        location: LatLng(52.2297, 21.0122),
        timezone: 'Europe/Warsaw',
        description: 'WTP / ZTM Warszawa',
      ),
      const City(
        id: 'krakow',
        name: 'Kraków',
        location: LatLng(50.0647, 19.9450),
        timezone: 'Europe/Warsaw',
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          apiClientProvider.overrideWithValue(
            FakeZbiorkomApiClient(fakeCities),
          ),
        ],
        child: const ZbiorkomMobileApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Warszawa'), findsOneWidget);
    expect(find.text('Kraków'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
  });
}
