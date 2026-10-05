import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/documents/presentation/document_detail_screen.dart';
import '../../features/documents/presentation/documents_screen.dart';
import '../../features/documents/presentation/processing_screen.dart';
import '../../features/documents/presentation/summary_screen.dart';
import '../../features/documents/presentation/upload_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/home/presentation/home_shell.dart';
import '../../features/profile/presentation/pro_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/settings_screen.dart';
import '../../features/viewer/presentation/pdf_viewer_screen.dart';

/// Screens reachable without a session.
const _publicPaths = {'/', '/onboarding', '/login'};

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final isPublic = _publicPaths.contains(state.matchedLocation);
      // While the session is still being restored the splash screen decides
      if (!auth.hasValue || isPublic) return null;
      return auth.value == null ? '/login' : null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/documents',
                builder: (context, state) => const DocumentsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/upload',
        builder: (context, state) => const UploadScreen(),
      ),
      GoRoute(
        path: '/documents/:id',
        builder: (context, state) =>
            DocumentDetailScreen(documentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/documents/:id/processing',
        builder: (context, state) =>
            ProcessingScreen(documentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/documents/:id/summary',
        builder: (context, state) =>
            SummaryScreen(documentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/documents/:id/view',
        builder: (context, state) =>
            PdfViewerScreen(documentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/documents/:id/chat',
        builder: (context, state) => ChatScreen(
          documentId: state.pathParameters['id']!,
          conversationId: state.uri.queryParameters['conversationId'],
          initialQuestion: state.uri.queryParameters['q'],
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(path: '/pro', builder: (context, state) => const ProScreen()),
    ],
  );

  // An expired session (refresh token rejected) sends the user to login
  // from wherever they are.
  ref.listen(authControllerProvider, (previous, next) {
    final wasSignedIn = previous?.value != null;
    if (wasSignedIn && next.hasValue && next.value == null) {
      router.go('/login');
    }
  });

  ref.onDispose(router.dispose);
  return router;
});
