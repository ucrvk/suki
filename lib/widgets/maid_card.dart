import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

enum MaidStatus { available, full, closed }

class MaidCard extends StatelessWidget {
  const MaidCard({
    super.key,
    required this.maid,
    required this.status,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onBook,
    required this.submitting,
  });

  final Map<String, dynamic> maid;
  final MaidStatus status;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onBook;
  final bool submitting;

  @override
  Widget build(BuildContext context) {
    final name = (maid['name'] ?? '未命名').toString();
    final image = (maid['image'] ?? '').toString();
    final signature = (maid['signature'] ?? '').toString();
    final tags = (maid['tags'] as List?)?.map((e) => e.toString()).toList() ?? [];

    final canBook = status == MaidStatus.available;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: image.isEmpty
                ? const ColoredBox(
                    color: Color(0xFFECDCF2),
                    child: Center(child: Icon(Icons.image_not_supported_outlined)),
                  )
                : CachedNetworkImage(
                    imageUrl: image,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const ColoredBox(
                      color: Color(0xFFECDCF2),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => const ColoredBox(
                      color: Color(0xFFECDCF2),
                      child: Center(child: Icon(Icons.broken_image_outlined)),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF3A3250),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onToggleFavorite,
                      splashRadius: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                        color: isFavorite ? const Color(0xFFFF5DAF) : const Color(0xFFB8AEC1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  signature.isEmpty ? '这位女仆还没有签名~' : signature,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFFF4FA5),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 8),
                if (tags.isNotEmpty)
                  SizedBox(
                    height: 28,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: tags.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 8),
                      itemBuilder: (context, index) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEAF4),
                          border: Border.all(color: const Color(0xFFFF8CC3)),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          tags[index],
                          style: const TextStyle(
                            color: Color(0xFFD31F7C),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 28),
                const SizedBox(height: 8),
                _buildBookButton(canBook: canBook, status: status),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookButton({
    required bool canBook,
    required MaidStatus status,
  }) {
    final enabled = canBook && !submitting;
    final label = canBook ? '预约' : (status == MaidStatus.full ? '预约已满' : '不营业');

    final bg = enabled ? const Color(0xFFFF6FB5) : const Color(0xFFD5CCD9);
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? onBook : null,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          disabledBackgroundColor: bg,
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        child: submitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(
                label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
      ),
    );
  }
}
