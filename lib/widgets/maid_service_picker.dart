import 'package:flutter/material.dart';

import '../utils/maid_services.dart';

/// 预约弹窗里的「玩什么」选择器。
///
/// - 多选时达到 [MaidServiceOptions.maxPick] 后，未选中的选项会被禁用；
/// - 单选（`maxPick == 1`）时点击新选项会直接替换旧选项；
/// - 允许一项都不选。
class MaidServicePicker extends StatelessWidget {
  const MaidServicePicker({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final MaidServiceOptions options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  void _toggle(String option) {
    final next = Set<String>.from(selected);
    if (next.contains(option)) {
      next.remove(option);
    } else if (options.isSingleChoice) {
      next
        ..clear()
        ..add(option);
    } else if (next.length >= options.maxPick) {
      return;
    } else {
      next.add(option);
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = options.isSingleChoice
        ? '单选'
        : options.hasLimit
        ? '可多选，最多 ${options.maxPick} 项'
        : '可多选';
    final count = options.hasLimit
        ? '已选 ${selected.length}/${options.maxPick}'
        : '已选 ${selected.length}';

    return Column(
      key: const Key('maid-service-picker'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text('玩什么', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              count,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final option in options.options)
              if (options.isSingleChoice)
                ChoiceChip(
                  key: Key('maid-service-$option'),
                  label: Text(option),
                  selected: selected.contains(option),
                  showCheckmark: false,
                  selectedColor: theme.colorScheme.primary,
                  labelStyle: selected.contains(option)
                      ? TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w700,
                        )
                      : null,
                  onSelected: (_) => _toggle(option),
                )
              else
                FilterChip(
                  key: Key('maid-service-$option'),
                  label: Text(option),
                  selected: selected.contains(option),
                  showCheckmark: false,
                  selectedColor: theme.colorScheme.primary,
                  labelStyle: selected.contains(option)
                      ? TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w700,
                        )
                      : null,
                  onSelected:
                      !selected.contains(option) &&
                          selected.length >= options.maxPick
                      ? null
                      : (_) => _toggle(option),
                ),
          ],
        ),
      ],
    );
  }
}
