class ApiConfig {
  const ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'ZBIORKOM_API_BASE',
    defaultValue: 'https://api.zbiorkom.live',
  );

  static const String cloudBaseUrl = String.fromEnvironment(
    'ZBIORKOM_CLOUD_BASE',
    defaultValue: 'https://4.zbiorkom.live',
  );

  static String? _runtimeBaseUrl;

  static String get effectiveBaseUrl {
    final custom = _runtimeBaseUrl?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom.endsWith('/')
          ? custom.substring(0, custom.length - 1)
          : custom;
    }
    return baseUrl;
  }

  static void setRuntimeBaseUrl(String? url) {
    _runtimeBaseUrl = url?.trim();
  }

  static const String connectivityProbeUrl =
      'https://www.gstatic.com/generate_204';

  static Uri api6Uri([String path = '', Map<String, dynamic>? queryParameters]) {
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final fullPath = normalizedPath.isEmpty ? '/api6' : '/api6/$normalizedPath';
    final base = Uri.parse(effectiveBaseUrl);

    final filteredQuery = <String, String>{};
    queryParameters?.forEach((key, value) {
      if (value != null && value.toString().isNotEmpty) {
        filteredQuery[key] = value.toString();
      }
    });

    return base.replace(
      path: fullPath,
      queryParameters: filteredQuery.isEmpty ? null : filteredQuery,
    );
  }
}
