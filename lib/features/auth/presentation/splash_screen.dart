import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/app_prefs.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../application/auth_controller.dart';

/// Shows the brand while the stored session is restored, then routes to
/// onboarding, login or home.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  static const _minimumDisplay = Duration(milliseconds: 1200);

  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait<Object?>([
        ref.read(authControllerProvider.future),
        Future<Object?>.delayed(_minimumDisplay),
      ]);
      if (!mounted) return;
      final signedIn = results.first != null;
      if (signedIn) {
        context.go(Routes.home);
      } else if (ref.read(appPrefsProvider).onboardingSeen) {
        context.go(Routes.login);
      } else {
        context.go(Routes.onboarding);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _retry() {
    ref.invalidate(authControllerProvider);
    _start();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 88),
                const SizedBox(height: 24),
                Text(AppConfig.appName, style: text.displaySmall),
                const SizedBox(height: 6),
                Text(
                  AppConfig.tagline,
                  style: text.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 40),
                if (_error == null)
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                else ...[
                  Text(
                    errorMessage(_error!),
                    style: text.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _retry,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(160, 48),
                    ),
                    child: const Text('Try again'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
