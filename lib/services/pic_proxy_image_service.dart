class PicProxyImageService {
  PicProxyImageService._();

  static const String _proxyBaseUrl =
      'https://api.wenwen12305.top/suki/pic-proxy/';

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
