import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/material.dart';

class TimedCachedNetworkImage extends StatefulWidget {
  const TimedCachedNetworkImage({
    super.key,
    required this.imageUrl,
    required this.placeholder,
    required this.errorWidget,
    this.fit,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.timeout = const Duration(seconds: 20),
  });

  final String imageUrl;
  final Widget Function(BuildContext, String) placeholder;
  final Widget Function(BuildContext, String, Object) errorWidget;
  final BoxFit? fit;
  final Alignment alignment;
  final double? width;
  final double? height;
  final Duration timeout;

  @override
  State<TimedCachedNetworkImage> createState() =>
      _TimedCachedNetworkImageState();
}

class _TimedCachedNetworkImageState extends State<TimedCachedNetworkImage> {
  bool _timedOut = false;

  @override
  void didUpdateWidget(covariant TimedCachedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) _timedOut = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_timedOut) {
      return widget.errorWidget(
        context,
        widget.imageUrl,
        TimeoutException('图片加载超时', widget.timeout),
      );
    }
    return CachedNetworkImage(
      key: ValueKey(widget.imageUrl),
      imageUrl: widget.imageUrl,
      imageRenderMethodForWeb: ImageRenderMethodForWeb.HtmlImage,
      fit: widget.fit,
      alignment: widget.alignment,
      width: widget.width,
      height: widget.height,
      placeholder: (context, url) => _TimedPlaceholder(
        timeout: widget.timeout,
        onTimeout: () {
          if (mounted) setState(() => _timedOut = true);
        },
        child: widget.placeholder(context, url),
      ),
      errorWidget: widget.errorWidget,
    );
  }
}

class _TimedPlaceholder extends StatefulWidget {
  const _TimedPlaceholder({
    required this.timeout,
    required this.onTimeout,
    required this.child,
  });

  final Duration timeout;
  final VoidCallback onTimeout;
  final Widget child;

  @override
  State<_TimedPlaceholder> createState() => _TimedPlaceholderState();
}

class _TimedPlaceholderState extends State<_TimedPlaceholder> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.timeout, () => widget.onTimeout());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
