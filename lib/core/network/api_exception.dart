/// An error returned by the API, or a failure to reach it.
class ApiException implements Exception {
  const ApiException({required this.message, this.name = 'Error', this.status});

  const ApiException.network()
    : message = 'No connection. Check your internet and try again.',
      name = 'NetworkError',
      status = null;

  /// Text written for the user.
  final String message;

  /// Machine-readable error name from the API, e.g. `DocumentLimitReached`.
  final String name;

  final int? status;

  bool get isNetwork => name == 'NetworkError';

  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;
}

/// Message to show for any error thrown by a repository call.
String errorMessage(Object error) {
  if (error is ApiException) return error.message;
  return 'Something went wrong. Please try again.';
}
