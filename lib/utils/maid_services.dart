/// 预约时可选的「玩什么」项目配置。
///
/// 数据直接来自 `suki_booking.maids` 里的原始字段：
/// `servicesEnabled` / `serviceOptions` / `serviceMaxPick`。
class MaidServiceOptions {
  const MaidServiceOptions({
    required this.enabled,
    required this.options,
    required this.maxPick,
  });

  final bool enabled;
  final List<String> options;

  /// 最多可选数量；配置缺失或无效时等于 [options] 的长度。
  final int maxPick;

  bool get isSelectable => enabled && options.isNotEmpty;

  bool get isSingleChoice => isSelectable && maxPick == 1;

  /// 配置了明确上限时，才展示「最多 N 项」。
  bool get hasLimit => isSelectable && maxPick < options.length;

  static MaidServiceOptions fromMaid(Map<String, dynamic> maid) {
    final rawOptions = maid['serviceOptions'];
    final options = <String>[];
    final seen = <String>{};
    if (rawOptions is List) {
      for (final raw in rawOptions) {
        final value = raw?.toString().trim() ?? '';
        if (value.isEmpty || !seen.add(value)) continue;
        options.add(value);
      }
    }

    final rawMax = maid['serviceMaxPick'];
    final parsedMax = rawMax is num
        ? rawMax.toInt()
        : int.tryParse(rawMax?.toString().trim() ?? '');
    final maxPick = options.isEmpty
        ? 0
        : (parsedMax == null || parsedMax <= 0
              ? options.length
              : (parsedMax > options.length ? options.length : parsedMax));

    return MaidServiceOptions(
      // 没有显式关闭（或没有该字段）时，只要存在选项就展示。
      enabled: maid['servicesEnabled'] != false,
      options: List.unmodifiable(options),
      maxPick: maxPick,
    );
  }

  /// 按 [options] 的原顺序过滤，过滤掉已不存在的选项。
  ///
  /// 使用有序集合，保证提交给后端的顺序稳定。
  Set<String> sanitizeSelection(Set<String> selected) {
    return {
      for (final option in options)
        if (selected.contains(option)) option,
    };
  }
}
