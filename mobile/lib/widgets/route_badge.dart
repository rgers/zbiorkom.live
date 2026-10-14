import 'package:flutter/material.dart';
import '../api/models.dart';
import '../core/transit_tools.dart';

class RouteBadge extends StatelessWidget {
  const RouteBadge({
    super.key,
    required this.route,
    this.subtitle,
    this.compact = false,
  });

  final TransitRoute route;
  final String? subtitle;
  final bool compact;

  IconData _iconForType(VehicleType type) {
    switch (type) {
      case VehicleType.tram:
        return Icons.tram;
      case VehicleType.subway:
        return Icons.subway;
      case VehicleType.train:
        return Icons.train;
      case VehicleType.ferry:
        return Icons.directions_boat;
      case VehicleType.trolleybus:
      case VehicleType.bus:
      case VehicleType.aerialLift:
      case VehicleType.funicular:
      case VehicleType.monorail:
        return Icons.directions_bus;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = TransitTools.parseHexColor(route.color);
    final label = subtitle != null && subtitle!.isNotEmpty
        ? '${route.name}/${subtitle!}'
        : route.name;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _iconForType(route.type),
            size: compact ? 12 : 14,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 11 : 13,
            ),
          ),
        ],
      ),
    );
  }
}
