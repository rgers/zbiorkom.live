import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/transit_tools.dart';
import '../../l10n/app_strings.dart';
import '../../state/app_providers.dart';
import '../../widgets/route_badge.dart';

class RoutesScreen extends ConsumerStatefulWidget {
  const RoutesScreen({
    super.key,
    required this.city,
  });

  final String city;

  @override
  ConsumerState<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends ConsumerState<RoutesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final strings = AppStrings(settings.languageCode);
    final routesAsync = ref.watch(cityRoutesProvider(widget.city));
    final filterState = ref.watch(cityFilterProvider(widget.city));

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.routes),
      ),
      body: Column(
        children: [
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
            child: routesAsync.when(
              data: (routes) {
                final q = TransitTools.normalizeSearch(_query.trim());
                final filtered = routes.where((r) {
                  if (q.isEmpty) return true;
                  return TransitTools.normalizeSearch(r.name).contains(q) ||
                      TransitTools.normalizeSearch(r.longName).contains(q);
                }).toList();

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final route = filtered[index];
                    final isSelected = filterState.routes.any(
                      (r) => r.id == route.id,
                    );
                    return ListTile(
                      leading: RouteBadge(route: route),
                      title: Text(
                        route.longName.isNotEmpty ? route.longName : route.name,
                      ),
                      subtitle: route.agency.isNotEmpty
                          ? Text(route.agency)
                          : null,
                      trailing: Icon(
                        isSelected
                            ? Icons.filter_alt
                            : Icons.filter_alt_outlined,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      onTap: () {
                        ref
                            .read(cityFilterProvider(widget.city).notifier)
                            .toggleRoute(route);
                        context.go('/${widget.city}');
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(child: Text(strings.serverError)),
            ),
          ),
        ],
      ),
    );
  }
}
