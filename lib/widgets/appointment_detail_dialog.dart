import 'package:flutter/material.dart';

import '../utils/reservation_details.dart';

/// 排班页的预约详情小窗。
class AppointmentDetailDialog extends StatelessWidget {
  const AppointmentDetailDialog({super.key, required this.details});

  final ReservationDetails details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final labelColor = theme.colorScheme.onSurfaceVariant;
    final serviceBg = isDark
        ? const Color(0xFF3A2A35)
        : const Color(0xFFFFEAF4);
    final serviceBorder = isDark
        ? const Color(0xFF7C3F64)
        : const Color(0xFFFF8CC3);
    final serviceText = isDark
        ? const Color(0xFFFFAAD6)
        : const Color(0xFFD31F7C);

    return AlertDialog(
      title: Text(
        details.timeSlot.isEmpty ? '预约详情' : '预约详情 · ${details.timeSlot}',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(
              label: '预约人',
              value: details.guestDisplay,
              labelColor: labelColor,
            ),
            const SizedBox(height: 10),
            _DetailRow(
              label: '预约目标',
              value: details.maidDisplay,
              labelColor: labelColor,
            ),
            if (details.withFriend) ...[
              const SizedBox(height: 10),
              _DetailRow(
                label: '携带好友',
                value: details.friendDisplay,
                labelColor: labelColor,
              ),
            ],
            if (details.services.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '玩什么',
                style: TextStyle(
                  color: labelColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final service in details.services)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: serviceBg,
                        border: Border.all(color: serviceBorder),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        service,
                        style: TextStyle(
                          color: serviceText,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.labelColor,
  });

  final String label;
  final String value;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(color: labelColor, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
