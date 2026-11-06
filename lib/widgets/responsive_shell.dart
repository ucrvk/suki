import 'package:flutter/material.dart';

/// 一个导航项（底部导航栏与左侧导航栏共用）。
class ShellDestination {
  const ShellDestination({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// 告诉页面当前是否处于「左侧导航栏」布局，页面据此隐藏顶栏等。
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required this.wide, required super.child});

  final bool wide;

  static bool isWide(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>()?.wide ?? false;

  @override
  bool updateShouldNotify(ShellScope oldWidget) => oldWidget.wide != wide;
}

/// 响应式外壳：
///
/// - 宽且不太矮（宽 ≥ [railBreakpoint]，高 ≥ [railMinHeight]）时使用左侧导航栏；
/// - 高度足够用大尺寸左栏，不够则用紧凑尺寸，再不够时导航项区域可滚动；
/// - 窗口太小（宽或高不足）直接回退到底部 [NavigationBar]。
class ResponsiveShell extends StatefulWidget {
  const ResponsiveShell({
    super.key,
    required this.body,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.railTrailing,
    this.logoAsset = 'assets/icon_board_inverse.png',
  });

  static const double railBreakpoint = 840;
  static const double railMinHeight = 500;
  static const Key railKey = Key('app-rail');
  static const Key railLogoKey = Key('app-rail-logo');
  static const double _railWidth = 92;

  static bool isWide(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width >= railBreakpoint && size.height >= railMinHeight;
  }

  /// 导航项下标（注意不是 IndexedStack 的页面下标）。
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<ShellDestination> destinations;

  /// 左栏底部内容（退出登录等），固定在最下方。
  final Widget? railTrailing;

  /// 反相蒙板：整块不透明、中间图形镂空，用于「外框涂色、中间透明」的样式。
  final String logoAsset;
  final Widget body;

  @override
  State<ResponsiveShell> createState() => _ResponsiveShellState();
}

class _ResponsiveShellState extends State<ResponsiveShell> {
  final GlobalKey _bodyKey = GlobalKey();

  Widget _bodyWithScope({required bool wide}) {
    return ShellScope(key: _bodyKey, wide: wide, child: widget.body);
  }

  @override
  Widget build(BuildContext context) {
    final wide = ResponsiveShell.isWide(context);

    if (!wide) {
      return Scaffold(
        body: _bodyWithScope(wide: false),
        bottomNavigationBar: NavigationBar(
          selectedIndex: widget.selectedIndex,
          onDestinationSelected: widget.onDestinationSelected,
          destinations: [
            for (final destination in widget.destinations)
              NavigationDestination(
                icon: Icon(destination.icon),
                label: destination.label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  _buildRail(context, constraints.maxHeight),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _bodyWithScope(wide: true)),
        ],
      ),
    );
  }

  Widget _buildLogo(BuildContext context, _RailMetrics metrics) {
    // 白天 / 夜间都用同一张反相蒙板：外框涂色、中间镂空透出页面背景。
    // 颜色在白天用较浅的深粉，在夜间用更浅的粉，始终比剪影底色浅。
    return Container(
      key: ResponsiveShell.railLogoKey,
      width: metrics.logoSize,
      height: metrics.logoSize,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(metrics.logoRadius),
      ),
      child: Image.asset(
        widget.logoAsset,
        fit: BoxFit.contain,
        color: metrics.logoFrameColor(context),
        colorBlendMode: BlendMode.srcIn,
      ),
    );
  }

  Widget _buildRail(BuildContext context, double height) {
    // 高度足够用大尺寸；不够用紧凑尺寸；再不够时中间区域自动滚动。
    final metrics = height >= _RailMetrics.bigThreshold
        ? _RailMetrics.big
        : _RailMetrics.small;

    return SizedBox(
      key: ResponsiveShell.railKey,
      width: ResponsiveShell._railWidth,
      child: Column(
        children: [
          // logo 永远贴在最上方，不随内容高度居中。
          // 蒙板图是透明底的黑色剪影，用 srcIn 染成主题粉色：
          // 白天深粉、夜间浅粉，外面套一个比剪影浅一档的圆角底色框。
          Padding(
            padding: EdgeInsets.fromLTRB(0, metrics.logoTop, 0, 10),
            child: _buildLogo(context, metrics),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (
                    var index = 0;
                    index < widget.destinations.length;
                    index++
                  )
                    _RailItem(
                      destination: widget.destinations[index],
                      selected: index == widget.selectedIndex,
                      metrics: metrics,
                      onTap: () => widget.onDestinationSelected(index),
                    ),
                ],
              ),
            ),
          ),
          ?widget.railTrailing,
        ],
      ),
    );
  }
}

class _RailMetrics {
  const _RailMetrics({
    required this.logoSize,
    required this.logoTop,
    required this.logoRadius,
    required this.iconSize,
    required this.pillWidth,
    required this.pillHeight,
    required this.labelSize,
    required this.itemPadding,
  });

  static const double bigThreshold = 820;

  static const _RailMetrics big = _RailMetrics(
    logoSize: 56,
    logoTop: 12,
    logoRadius: 17,
    iconSize: 26,
    pillWidth: 54,
    pillHeight: 32,
    labelSize: 13,
    itemPadding: 6,
  );

  static const _RailMetrics small = _RailMetrics(
    logoSize: 33,
    logoTop: 6,
    logoRadius: 13,
    iconSize: 20,
    pillWidth: 44,
    pillHeight: 28,
    labelSize: 11,
    itemPadding: 2,
  );

  final double logoSize;
  final double logoTop;
  final double logoRadius;
  final double iconSize;
  final double pillWidth;
  final double pillHeight;
  final double labelSize;
  final double itemPadding;

  /// 圆角框颜色：同一支深粉，白天多兑白（更浅），夜间少兑白（更深）。
  Color logoFrameColor(BuildContext context) {
    final mixWhite = Theme.of(context).brightness == Brightness.dark
        ? 0.12
        : 0.72;
    return Color.lerp(const Color(0xFFD31F7C), Colors.white, mixWhite)!;
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.metrics,
    required this.onTap,
  });

  final ShellDestination destination;
  final bool selected;
  final _RailMetrics metrics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: metrics.itemPadding,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: metrics.pillWidth,
                height: metrics.pillHeight,
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.secondaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(
                  destination.icon,
                  size: metrics.iconSize,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                destination.label,
                style: TextStyle(
                  fontSize: metrics.labelSize,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
