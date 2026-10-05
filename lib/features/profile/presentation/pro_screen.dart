import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/application/auth_controller.dart';

/// Plan comparison. Purchasing is not wired up in V1, so the call to action
/// is disabled until billing is added.
class ProScreen extends ConsumerWidget {
  const ProScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final isPro = ref.watch(currentUserProvider)?.isPro ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('PDF Genesis Pro')),
      body: ContentWidth(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Icon(
                          Icons.bolt_rounded,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Unlock PDF Genesis Pro',
                      style: text.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'More room for the documents you work with.',
                      style: text.bodyLarge?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    _PlanCard(
                      name: 'Pro',
                      highlighted: true,
                      current: isPro,
                      features: const [
                        'Store up to ${AppConfig.proMaxDocuments} PDFs',
                        'AI summaries with key points',
                        'Chat with page references',
                      ],
                    ),
                    const SizedBox(height: 12),
                    _PlanCard(
                      name: 'Free',
                      highlighted: false,
                      current: !isPro,
                      features: const [
                        'Store up to ${AppConfig.freeMaxDocuments} PDFs',
                        'AI summaries with key points',
                        'Chat with page references',
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    FilledButton(
                      onPressed: null,
                      child: Text(isPro ? 'You are on Pro' : 'Coming soon'),
                    ),
                    if (!isPro) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Pro subscriptions are not available yet.',
                        style: text.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.name,
    required this.features,
    required this.highlighted,
    required this.current,
  });

  final String name;
  final List<String> features;
  final bool highlighted;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? AppColors.primary : AppColors.border,
          width: highlighted ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(name, style: text.titleLarge),
              const Spacer(),
              if (current)
                const Pill(
                  label: 'CURRENT',
                  foreground: AppColors.textSecondary,
                  background: AppColors.surfaceMuted,
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final feature in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: highlighted
                        ? AppColors.primary
                        : AppColors.textSubtle,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(feature, style: text.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
