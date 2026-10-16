import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'remote_image.dart';

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({required this.imageUrl, this.size = 48, super.key});

  final String imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      key: const Key('account-avatar-fallback'),
      width: size,
      height: size,
      color: AppColors.field,
      alignment: Alignment.center,
      child: Icon(
        Icons.person_rounded,
        size: size * 0.55,
        color: AppColors.textPrimary,
      ),
    );
    return ClipOval(
      child: RemoteImage(
        imageUrl: imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: fallback,
        errorWidget: fallback,
      ),
    );
  }
}
