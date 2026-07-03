import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/pic_proxy_image_service.dart';

class ProxyFallbackImage extends StatefulWidget {
  const ProxyFallbackImage({
    super.key,
    required this.imageUrl,
    required this.placeholder,
    required this.errorWidget,
    this.fit,
    this.alignment = Alignment.center,
    this.width,
    this.height,
  });

  final String imageUrl;
  final Widget Function(BuildContext context, String url) placeholder;
  final Widget Function(BuildContext context, String url, Object error)
  errorWidget;
  final BoxFit? fit;
  final Alignment alignment;
  final double? width;
  final double? height;

  @override
  State<ProxyFallbackImage> createState() => _ProxyFallbackImageState();
}

class _ProxyFallbackImageState extends State<ProxyFallbackImage> {
  late String _activeUrl;
  String? _proxyUrl;
  bool _triedProxy = false;

  @override
  void initState() {
    super.initState();
    _configureForImage(widget.imageUrl);
  }

  @override
  void didUpdateWidget(covariant ProxyFallbackImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _configureForImage(widget.imageUrl);
    }
  }

  void _configureForImage(String imageUrl) {
    _activeUrl = imageUrl;
    _proxyUrl = PicProxyImageService.buildProxyUrl(imageUrl);
    _triedProxy = false;
  }

  void _switchToProxy() {
    if (_triedProxy || _proxyUrl == null) return;
    setState(() {
      _triedProxy = true;
      _activeUrl = _proxyUrl!;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: _activeUrl,
      fit: widget.fit,
      alignment: widget.alignment,
      width: widget.width,
      height: widget.height,
      placeholder: widget.placeholder,
      errorWidget: (context, url, error) {
        final shouldRetryWithProxy =
            !_triedProxy && _proxyUrl != null && _activeUrl == widget.imageUrl;
        if (shouldRetryWithProxy) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _switchToProxy();
          });
          return widget.placeholder(context, url);
        }
        return widget.errorWidget(context, url, error);
      },
    );
  }
}
