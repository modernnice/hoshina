class NetworkErrorHelper {
  static bool isNetworkErrorMessage(String? message) {
    if (message == null || message.trim().isEmpty) {
      return false;
    }
    final text = message.toLowerCase();
    return text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection refused') ||
        text.contains('connection reset') ||
        text.contains('timed out') ||
        text.contains('dns') ||
        text.contains('network');
  }
}
