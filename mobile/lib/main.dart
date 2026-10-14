import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api/api_client.dart';
import 'l10n/app_strings.dart';
import 'routing/app_router.dart';
import 'state/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const ZbiorkomMobileApp(),
    ),
  );
}

class ZbiorkomMobileApp extends ConsumerStatefulWidget {
  const ZbiorkomMobileApp({super.key});

  @override
  ConsumerState<ZbiorkomMobileApp> createState() => _ZbiorkomMobileAppState();
}

class _ZbiorkomMobileAppState extends ConsumerState<ZbiorkomMobileApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(backendBootstrapProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final bootstrap = ref.watch(backendBootstrapProvider);
    final router = ref.watch(appRouterProvider);
    final strings = AppStrings(settings.languageCode);

    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: settings.seedColor,
    );

    if (bootstrap.isLoading && bootstrap.cities.isEmpty) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (bootstrap.error != null && bootstrap.cities.isEmpty) {
      final isNetwork = bootstrap.error!.kind == BackendErrorKind.network;
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isNetwork ? Icons.wifi_off : Icons.cloud_off,
                    size: 56,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isNetwork ? strings.networkError : strings.serverError,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      ref.read(backendBootstrapProvider.notifier).load();
                    },
                    icon: const Icon(Icons.refresh),
                    label: Text(strings.retry),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: strings.appTitle,
      theme: theme,
      locale: Locale(settings.languageCode),
      supportedLocales: const [Locale('pl'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}
