import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/app_strings.dart';
import '../../state/app_providers.dart';

class FavoriteStopsScreen extends ConsumerWidget {
  const FavoriteStopsScreen({
    super.key,
    required this.city,
  });

  final String city;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final strings = AppStrings(settings.languageCode);
    final favorites = ref.watch(favoriteStopsProvider(city));

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.favoriteStops),
      ),
      body: favorites.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  strings.emptyFavorites,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              itemCount: favorites.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final fav = favorites[index];
                return ListTile(
                  leading: Icon(fav.isStation ? Icons.train : Icons.place),
                  title: Text(fav.name),
                  subtitle: fav.code.isNotEmpty ? Text('#${fav.code}') : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      ref
                          .read(favoriteStopsProvider(city).notifier)
                          .toggleStop(fav);
                    },
                  ),
                  onTap: () {
                    final kind = fav.isStation ? 'station' : 'stop';
                    context.go(
                      '/$city/$kind/${Uri.encodeComponent(fav.id)}',
                    );
                  },
                );
              },
            ),
    );
  }
}
