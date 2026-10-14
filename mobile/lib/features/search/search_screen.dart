import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../api/models.dart';
import '../../core/transit_tools.dart';
import '../../l10n/app_strings.dart';
import '../../state/app_providers.dart';
import '../../widgets/route_badge.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({
    super.key,
    required this.city,
  });

  final String city;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  CancelToken? _cancelToken;
  SearchResultsBundle? _results;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _cancelToken?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String raw) {
    _debounce?.cancel();
    _cancelToken?.cancel();
    final query = raw.trim();
    if (query.isEmpty) {
      setState(() {
        _results = null;
        _isLoading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final token = CancelToken();
      _cancelToken = token;
      try {
        final res = await ref
            .read(apiClientProvider)
            .searchCity(widget.city, query, cancelToken: token);
        if (!mounted) return;
        setState(() {
          _results = res;
          _isLoading = false;
        });
      } catch (e) {
        if (token.isCancelled || !mounted) return;
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final strings = AppStrings(settings.languageCode);
    final entries = _results?.results ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onQueryChanged,
          decoration: InputDecoration(
            hintText: strings.searchHint,
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                _onQueryChanged('');
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(strings.serverError))
          : entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  strings.searchHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          : ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = entries[index];
                if (item.vehicle != null) {
                  final v = item.vehicle!;
                  return ListTile(
                    leading: RouteBadge(route: v.route, subtitle: v.brigade),
                    title: Text(v.headsign ?? '#${v.id}'),
                    subtitle: Text(
                      [
                        '#${v.id}',
                        if (v.model != null && v.model!.isNotEmpty) v.model!,
                      ].join(' · '),
                    ),
                    onTap: () {
                      final suffix = TransitTools.buildCitySuffix(
                        v.route.city,
                        widget.city,
                      );
                      context.go(
                        '/${widget.city}/vehicle/${Uri.encodeComponent(v.id)}$suffix',
                      );
                    },
                  );
                }

                if (item.stop != null || item.station != null) {
                  final s = (item.station ?? item.stop)!;
                  final firstStop = s.stops.isNotEmpty ? s.stops.first : null;
                  final targetId = firstStop?.id ?? s.id;
                  return ListTile(
                    leading: Icon(
                      s.isStation ? Icons.train : Icons.place_outlined,
                    ),
                    title: Text(s.name),
                    subtitle: firstStop != null && firstStop.routes.isNotEmpty
                        ? Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: firstStop.routes
                                .take(8)
                                .map((r) => RouteBadge(route: r, compact: true))
                                .toList(),
                          )
                        : null,
                    onTap: () {
                      final kind = s.isStation ? 'station' : 'stop';
                      final suffix = TransitTools.buildCitySuffix(
                        s.city,
                        widget.city,
                      );
                      context.go(
                        '/${widget.city}/$kind/${Uri.encodeComponent(targetId)}$suffix',
                      );
                    },
                  );
                }

                if (item.route != null) {
                  final r = item.route!;
                  return ListTile(
                    leading: RouteBadge(route: r),
                    title: Text(r.longName.isNotEmpty ? r.longName : r.name),
                    subtitle: Text(r.agency),
                    onTap: () {
                      ref
                          .read(cityFilterProvider(widget.city).notifier)
                          .toggleRoute(r);
                      context.go('/${widget.city}');
                    },
                  );
                }

                if (item.relation != null) {
                  final rel = item.relation!;
                  return ListTile(
                    leading: RouteBadge(route: rel.route),
                    title: Text('${rel.shortName} → ${rel.headsign}'),
                    subtitle: Text(
                      '${TransitTools.formatTimeHHmm(rel.startMs)} - ${TransitTools.formatTimeHHmm(rel.endMs)}',
                    ),
                    onTap: () {
                      context.go(
                        '/${widget.city}/trip/${Uri.encodeComponent(rel.id)}',
                      );
                    },
                  );
                }

                return const SizedBox.shrink();
              },
            ),
    );
  }
}
