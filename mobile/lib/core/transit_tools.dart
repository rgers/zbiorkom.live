import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

enum DelayClassification { delayed, early, onTime, unknown }

class DelayPresentation {
  const DelayPresentation({
    required this.classification,
    required this.formattedDuration,
  });

  final DelayClassification classification;
  final String formattedDuration;
}

class TransitTools {
  const TransitTools._();

  static String formatTimeHHmm(int epochMs) {
    if (epochMs <= 0) return '--:--';
    final date = DateTime.fromMillisecondsSinceEpoch(epochMs);
    return DateFormat('HH:mm').format(date);
  }

  static String msToTime(int ms, {bool withSeconds = false}) {
    final parts = <String>[];
    final totalSeconds = (ms.abs() / 1000).floor();
    final totalMinutes = (totalSeconds / 60).floor();
    final hours = (totalMinutes / 60).floor();

    final remainingMinutes = totalMinutes % 60;
    final remainingSeconds = totalSeconds % 60;

    if (hours > 0) parts.add('$hours h');
    if (remainingMinutes > 0) parts.add('$remainingMinutes min');
    if (withSeconds) parts.add('$remainingSeconds s');

    return parts.join(' ');
  }

  static DelayPresentation classifyDelay(int? delayMs) {
    if (delayMs == null) {
      return const DelayPresentation(
        classification: DelayClassification.unknown,
        formattedDuration: '',
      );
    }

    final durationText = msToTime(delayMs.abs());
    if (durationText.isEmpty) {
      return const DelayPresentation(
        classification: DelayClassification.onTime,
        formattedDuration: '',
      );
    }

    return DelayPresentation(
      classification: delayMs > 0
          ? DelayClassification.delayed
          : DelayClassification.early,
      formattedDuration: durationText,
    );
  }

  static int getDaysSince2020(DateTime dateTimeUtcOrLocal) {
    final dayUtc = DateTime.utc(
      dateTimeUtcOrLocal.year,
      dateTimeUtcOrLocal.month,
      dateTimeUtcOrLocal.day,
    );
    return (dayUtc.millisecondsSinceEpoch ~/ 86400000) - 18262;
  }

  static List<LatLng> decodePolyline6(String encoded) {
    if (encoded.isEmpty) return const [];
    const factor = 1e6;
    var index = 0;
    var lat = 0;
    var lng = 0;
    final points = <LatLng>[];

    while (index < encoded.length) {
      var b = 0;
      var shift = 0;
      var result = 0;

      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && index < encoded.length);

      final dLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dLat;

      shift = 0;
      result = 0;

      if (index >= encoded.length) break;

      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && index < encoded.length);

      final dLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dLng;

      points.add(LatLng(lat / factor, lng / factor));
    }

    return points;
  }

  static const Map<String, String> _polishFold = {
    'ą': 'a',
    'ć': 'c',
    'ę': 'e',
    'ł': 'l',
    'ń': 'n',
    'ó': 'o',
    'ś': 's',
    'ź': 'z',
    'ż': 'z',
  };

  static String normalizeSearch(String value) {
    final lower = value.toLowerCase();
    final buffer = StringBuffer();
    for (var i = 0; i < lower.length; i++) {
      final ch = lower[i];
      buffer.write(_polishFold[ch] ?? ch);
    }
    return buffer.toString();
  }

  static String buildCitySuffix(String? entityCity, String? routeCity) {
    if (entityCity == null || entityCity.isEmpty || entityCity == routeCity) {
      return '';
    }
    return '?city=${Uri.encodeQueryComponent(entityCity)}';
  }

  static Color parseHexColor(String? hex, {Color fallback = const Color(0xFF276B2B)}) {
    if (hex == null || hex.isEmpty) return fallback;
    final cleaned = hex.replaceFirst('#', '').trim();
    if (cleaned.length == 6) {
      final parsed = int.tryParse('FF$cleaned', radix: 16);
      if (parsed != null) return Color(parsed);
    } else if (cleaned.length == 8) {
      final parsed = int.tryParse(cleaned, radix: 16);
      if (parsed != null) return Color(parsed);
    }
    return fallback;
  }
}
