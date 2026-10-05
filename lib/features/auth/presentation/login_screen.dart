import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/router/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../application/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _signingIn = false;

  late final _termsTap = TapGestureRecognizer()
    ..onTap = () => openExternalUrl(context, AppConfig.termsUrl);
  late final _privacyTap = TapGestureRecognizer()
    ..onTap = () => openExternalUrl(context, AppConfig.privacyPolicyUrl);

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  Future<void> _google() async {
    setState(() => _signingIn = true);
    try {
      final signedIn = await ref
          .read(authControllerProvider.notifier)
          .signInWithGoogle();
      if (signedIn && mounted) context.go(Routes.home);
    } catch (error) {
      if (mounted) showAppSnackBar(context, errorMessage(error));
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const link = TextStyle(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );

    return Scaffold(
      body: ContentWidth(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AppLogo(),
                    const SizedBox(height: 16),
                    Text(AppConfig.appName, style: text.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                      AppConfig.tagline,
                      style: text.bodyLarge?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: AppColors.border),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.asset(
                            'assets/images/login.jpg',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    OutlinedButton(
                      onPressed: _signingIn ? null : _google,
                      child: _signingIn
                          ? const _ButtonSpinner()
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _GoogleMark(),
                                SizedBox(width: 12),
                                Flexible(child: Text('Continue with Google')),
                              ],
                            ),
                    ),
                    const SizedBox(height: 20),
                    Text.rich(
                      TextSpan(
                        text: 'By continuing you agree to our ',
                        children: [
                          TextSpan(
                            text: 'Terms',
                            style: link,
                            recognizer: _termsTap,
                          ),
                          const TextSpan(text: ' and '),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: link,
                            recognizer: _privacyTap,
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                      style: text.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2.5),
    );
  }
}

/// The four-colour Google "G", drawn so no image asset is needed.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleMarkPainter()),
    );
  }
}

class _GoogleMarkPainter extends CustomPainter {
  const _GoogleMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.2;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    Paint arc(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    const degree = 3.141592653589793 / 180;
    canvas
      ..drawArc(
        rect,
        -45 * degree,
        -90 * degree,
        false,
        arc(const Color(0xFFEA4335)),
      )
      ..drawArc(
        rect,
        -135 * degree,
        -90 * degree,
        false,
        arc(const Color(0xFFFBBC05)),
      )
      ..drawArc(
        rect,
        135 * degree,
        -90 * degree,
        false,
        arc(const Color(0xFF34A853)),
      )
      ..drawArc(
        rect,
        45 * degree,
        -45 * degree,
        false,
        arc(const Color(0xFF4285F4)),
      )
      ..drawRect(
        Rect.fromLTWH(
          size.width / 2,
          size.height / 2 - stroke / 2,
          size.width / 2,
          stroke,
        ),
        Paint()..color = const Color(0xFF4285F4),
      );
  }

  @override
  bool shouldRepaint(_GoogleMarkPainter oldDelegate) => false;
}
