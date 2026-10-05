/// Locations of the screens that take parameters, so no screen builds a
/// route string by hand.
class Routes {
  const Routes._();

  static const home = '/home';
  static const login = '/login';
  static const onboarding = '/onboarding';
  static const documents = '/documents';
  static const upload = '/upload';
  static const settings = '/settings';

  static String document(String id) => '/documents/$id';

  static String processing(String id) => '/documents/$id/processing';

  static String summary(String id) => '/documents/$id/summary';

  static String viewer(String id) => '/documents/$id/view';

  /// The chat screen, optionally resuming a conversation or sending a first
  /// question straight away.
  static String chat(
    String documentId, {
    String? conversationId,
    String? question,
  }) {
    return Uri(
      path: '/documents/$documentId/chat',
      queryParameters: {'conversationId': ?conversationId, 'q': ?question},
    ).toString();
  }
}
