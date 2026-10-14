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
          const SizedBox(height: 20),
          Text(
            strings.isPolish ? 'Serwer API (/api6)' : 'API Server (/api6)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Card(
            child: RadioGroup<String>(
              groupValue: settings.apiBaseUrl,
              onChanged: (val) async {
                if (val == null) return;
                await notifier.setApiBaseUrl(val);
                await ref.read(backendBootstrapProvider.notifier).load();
              },
              child: Column(
                children: [
                  const RadioListTile<String>(
                    value: 'https://api.zbiorkom.live',
                    title: Text('zbiorkom.live (Cloud)'),
                    subtitle: Text('https://api.zbiorkom.live'),
                  ),
                  RadioListTile<String>(
                    value: 'http://localhost:8005',
                    title: Text(
                      strings.isPolish
                          ? 'Lokalny backend .NET 10 (iOS / Web / Desktop)'
                          : 'Local .NET 10 Backend (iOS / Web / Desktop)',
                    ),
                    subtitle: const Text('http://localhost:8005'),
                  ),
                  RadioListTile<String>(
                    value: 'http://10.0.2.2:8005',
                    title: Text(
                      strings.isPolish
                          ? 'Lokalny backend .NET 10 (Emulator Android)'
                          : 'Local .NET 10 Backend (Android Emulator)',
                    ),
                    subtitle: const Text('http://10.0.2.2:8005'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
