import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/transit_tools.dart';
import '../../l10n/app_strings.dart';
import '../../state/app_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({
    super.key,
    required this.city,
  });

  final String city;

  static const List<String> _themeSwatches = [
    '#276b2b',
    '#1565c0',
    '#6a1b9a',
    '#ad1457',
    '#ef6c00',
    '#00838f',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final strings = AppStrings(settings.languageCode);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.settings),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.location_city),
              title: Text(strings.changeCity),
              subtitle: Text(city),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/cities'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            strings.language,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'pl', label: Text('Polski')),
              ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {settings.languageCode},
            onSelectionChanged: (selection) {
              notifier.setLanguage(selection.first);
            },
          ),
          const SizedBox(height: 20),
          Text(
            strings.changeTheme,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _themeSwatches.map((hex) {
              final color = TransitTools.parseHexColor(hex);
              final isSelected =
                  settings.themeColorHex.toLowerCase() == hex.toLowerCase();
              return GestureDetector(
                onTap: () => notifier.setThemeColor(hex),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: color,
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text(
            strings.vehicleMarker,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          SwitchListTile(
            value: settings.showBrigadeOnMarker,
            onChanged: notifier.setShowBrigadeOnMarker,
            title: Text(strings.showBrigade),
          ),
          SwitchListTile(
            value: settings.showFleetOnMarker,
            onChanged: notifier.setShowFleetOnMarker,
            title: Text(strings.showFleet),
          ),
          const SizedBox(height: 12),
          Text(
            strings.behavior,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          SwitchListTile(
            value: settings.moveToLastLocation,
            onChanged: notifier.setMoveToLastLocation,
            title: Text(strings.moveToLastLocation),
          ),
        ],
      ),
    );
  }
}
