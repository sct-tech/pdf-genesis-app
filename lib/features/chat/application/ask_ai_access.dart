import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';

/// Whether the current user may use Ask AI. Guests can upload, view and edit
/// PDFs, but asking questions needs a signed-in account. The server enforces
/// the same rule (`SignInRequired`).
final askAiAvailableProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider);
  return user != null && !user.isGuest;
});
