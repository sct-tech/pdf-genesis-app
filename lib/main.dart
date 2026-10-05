import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/services/ads_service.dart';
import 'core/storage/app_prefs.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/documents/data/pdf_file_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validate();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [appPrefsProvider.overrideWithValue(AppPrefs(prefs))],
      child: const PdfGenesisApp(),
    ),
  );
}

class PdfGenesisApp extends ConsumerStatefulWidget {
  const PdfGenesisApp({super.key});

  @override
  ConsumerState<PdfGenesisApp> createState() => _PdfGenesisAppState();
}

class _PdfGenesisAppState extends ConsumerState<PdfGenesisApp> {
  @override
  void initState() {
    super.initState();
    ref.read(adsProvider).initialize();
    // Someone else may use this device next: nothing of the previous
    // account's stays behind. A guest upgrading to Google keeps the same id.
    ref.listenManual(currentUserProvider.select((user) => user?.id), (
      previous,
      next,
    ) {
      if (previous == null || previous == next) return;
      ref.read(pdfFileStoreProvider).evictAll().catchError((_) {});
      ref.read(appPrefsProvider).clearSignature();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
