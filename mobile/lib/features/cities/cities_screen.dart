import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../api/models.dart';
import '../../core/transit_tools.dart';
import '../../l10n/app_strings.dart';
import '../../state/app_providers.dart';

class CitiesScreen extends ConsumerStatefulWidget {
  const CitiesScreen({super.key});

  @override
  ConsumerState<CitiesScreen> createState() => _CitiesScreenState();
}

class _CitiesScreenState extends ConsumerState<CitiesScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final bootstrap = ref.watch(backendBootstrapProvider);
    final settings = ref.watch(appSettingsProvider);
    final strings = AppStrings(settings.languageCode);

    final normalizedQuery = TransitTools.normalizeSearch(_search.trim());
    final cities = bootstrap.visibleCities.where((City city) {
      if (normalizedQuery.isEmpty) return true;
      final nameMatch = TransitTools.normalizeSearch(
        city.name,
      ).contains(normalizedQuery);
      final descMatch = city.description != null &&
          TransitTools.normalizeSearch(
            city.description!,
          ).contains(normalizedQuery);
      return nameMatch || descMatch;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.pickCity),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              onChanged: (value) => setState(() => _search = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: strings.searchCities,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: bootstrap.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: cities.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final city = cities[index];
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          leading: const CircleAvatar(
                            child: Icon(Icons.location_city),
                          ),
                          title: Text(
                            city.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: city.description != null &&
                                  city.description!.isNotEmpty
                              ? Text(city.description!)
                              : null,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await ref
                                .read(appSettingsProvider.notifier)
                                .setSelectedCity(city.id);
                            if (context.mounted) {
                              context.go('/${city.id}');
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
