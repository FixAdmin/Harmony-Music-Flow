class ProviderRequest {
  const ProviderRequest._();

  static Future<T> resolve<T>(
    Future<T> request, {
    required Duration timeout,
    required T fallback,
  }) async {
    try {
      return await request.timeout(timeout);
    } catch (_) {
      return fallback;
    }
  }
}
