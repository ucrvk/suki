import 'backend_config.dart';

class PicProxyImageService {
  PicProxyImageService._();

  static String get _proxyBaseUrl =>
      '${BackendConfig.normalizedBaseUrl}/pic-proxy/';

  static bool supportsProxy(String imageUrl) {
    final uri = Uri.tryParse(imageUrl.trim());
    return uri != null && uri.scheme.toLowerCase() == 'https';
  }

  static String? buildProxyUrl(String imageUrl) {
    final trimmed = imageUrl.trim();
    if (!supportsProxy(trimmed)) return null;
    return '$_proxyBaseUrl${Uri.encodeComponent(trimmed)}';
  }
}
