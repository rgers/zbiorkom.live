import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/transit_tools.dart';
import '../../l10n/app_strings.dart';
import '../../state/app_providers.dart';
import '../../widgets/route_badge.dart';

class FilterScreen extends ConsumerStatefulWidget {
  const FilterScreen({
    super.key,
    required this.city,
  });

  final String city;

  @override
  ConsumerState<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends ConsumerState<FilterScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final strings = AppStrings(settings.languageCode);
    final filter = ref.watch(cityFilterProvider(widget.city));
    final routesAsync = ref.watch(cityRoutesProvider(widget.city));
    final modelsAsync = ref.watch(cityModelsProvider(widget.city));

    final normalized = TransitTools.normalizeSearch(_query.trim());

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.filter),
        actions: [
          if (filter.isActive)
            TextButton(
              onPressed: () {
                ref.read(cityFilterProvider(widget.city).notifier).clear();
              },
              child: Text(strings.clearFilters),
            ),
        ],
      ),
      body: Column(
        children: [
          if (filter.isActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...filter.routes.map(
                      (r) => InputChip(
                        label: Text(r.name),
                        onDeleted: () => ref
                            .read(cityFilterProvider(widget.city).notifier)
                            .toggleRoute(r),
                      ),
                    ),
                    ...filter.models.map(
                      (m) => InputChip(
                        label: Text(m),
                        onDeleted: () => ref
                            .read(cityFilterProvider(widget.city).notifier)
                            .toggleModel(m),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: strings.searchRoutes,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                routesAsync.when(
                  data: (routes) {
                    final matched = routes.where((r) {
                      if (normalized.isEmpty) return true;
                      return TransitTools.normalizeSearch(
                            r.name,
                          ).contains(normalized) ||
                          TransitTools.normalizeSearch(
                            r.longName,
                          ).contains(normalized);
                    }).take(40);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            strings.routes,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: matched.map((route) {
                            final active = filter.routes.any(
                              (r) => r.id == route.id,
                            );
                            return FilterChip(
                              selected: active,
                              label: RouteBadge(route: route, compact: true),
                              onSelected: (_) {
                                ref
                                    .read(
                                      cityFilterProvider(widget.city).notifier,
                                    )
                                    .toggleRoute(route);
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 16),
                modelsAsync.when(
                  data: (models) {
                    final matched = models.where((m) {
                      if (normalized.isEmpty) return true;
                      return TransitTools.normalizeSearch(
                        m,
                      ).contains(normalized);
                    }).take(40);

                    if (matched.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            strings.model,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: matched.map((model) {
                            final active = filter.models.contains(model);
                            return FilterChip(
                              selected: active,
                              label: Text(model),
                              onSelected: (_) {
                                ref
                                    .read(
                                      cityFilterProvider(widget.city).notifier,
                                    )
                                    .toggleModel(model);
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
