import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/storage/app_prefs.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';

class _Slide {
  const _Slide(this.image, this.title, this.body);

  final String image;
  final String title;
  final String body;
}

const _slides = [
  _Slide(
    'assets/images/onboarding_1.jpg',
    'Understand Any PDF Instantly',
    'Upload documents and let AI understand the content for you.',
  ),
  _Slide(
    'assets/images/onboarding_2.jpg',
    'Ask Anything',
    'Chat directly with your documents and get instant answers.',
  ),
  _Slide(
    'assets/images/onboarding_3.jpg',
    'Save Hours of Reading',
    'Get summaries and important insights in seconds.',
  ),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _maxWidth = 900.0;

  final _controller = PageController();
  int _page = 0;

  bool get _isLast => _page == _slides.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(appPrefsProvider).setOnboardingSeen();
    if (mounted) context.go(Routes.login);
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          maxWidth: _maxWidth,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              children: [
                Row(
                  children: [
                    const AppLogo(size: 32),
                    const SizedBox(width: 10),
                    Text(AppConfig.appName, style: text.titleLarge),
                    const Spacer(),
                    // Kept in the layout on the last slide so nothing shifts
                    Visibility(
                      visible: !_isLast,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: TextButton(
                        onPressed: _finish,
                        child: const Text('Skip'),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _slides.length,
                    onPageChanged: (page) => setState(() => _page = page),
                    itemBuilder: (context, index) =>
                        _SlideView(slide: _slides[index]),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _slides.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _page ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _page
                              ? AppColors.primary
                              : AppColors.border,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: ContentWidths.toolbar,
                  ),
                  child: FilledButton(
                    onPressed: _next,
                    child: Text(_isLast ? 'Get Started' : 'Continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One slide: picture above the text, or beside it when the window is wider
/// than it is tall.
class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    final picture = AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(slide.image, fit: BoxFit.cover),
      ),
    );

    List<Widget> copy(TextAlign align) => [
      Text(slide.title, style: text.headlineMedium, textAlign: align),
      const SizedBox(height: 10),
      Text(
        slide.body,
        style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
        textAlign: align,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > constraints.maxHeight) {
          return Row(
            children: [
              Flexible(child: picture),
              const SizedBox(width: 32),
              Expanded(
                // Scrolls if large text does not fit the short window
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: copy(TextAlign.start),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: picture,
              ),
            ),
            const SizedBox(height: 32),
            ...copy(TextAlign.center),
          ],
        );
      },
    );
  }
}
