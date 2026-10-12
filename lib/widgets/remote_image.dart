import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 网络图片，带内存 + 磁盘缓存（`cached_network_image`）。
///
/// - 空地址直接渲染占位，不发起请求；
/// - 加载中显示 [placeholder]，失败显示 [errorWidget]（缺省都回落到空白占位）；
/// - 需要圆角时传 [borderRadius]，内部用 [ClipRRect] 裁切。
class RemoteImage extends StatelessWidget {
  const RemoteImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl.trim();
    final loading = placeholder ?? SizedBox(width: width, height: height);
    final failure = errorWidget ?? loading;
    if (url.isEmpty) return _clip(failure);
    return _clip(
      CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        placeholder: (_, _) => loading,
        errorWidget: (_, _, _) => failure,
      ),
    );
  }

  Widget _clip(Widget child) {
    final radius = borderRadius;
    if (radius == null) return child;
    return ClipRRect(borderRadius: radius, child: child);
  }
}
