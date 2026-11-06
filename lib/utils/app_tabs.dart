/// 逻辑 Tab ID 与布局无关：
///
/// - 窄屏把「介绍 / 评价 / 留言 / 照片墙」折叠成占位相同的「介绍」一项；
/// - 宽屏（左侧导航栏）把它们展开成四个导航项，但页面仍然是同一个
///   `FeedbackPage`，只是切换内部 segment。
///
/// 因此所有跨页面的跳转、双击回顶都使用这里的稳定 ID，而不是导航下标。
abstract final class AppTabs {
  static const int queue = 0;
  static const int booking = 1;
  static const int schedule = 2;
  static const int intro = 3;
  static const int reviews = 4;
  static const int guestbook = 5;
  static const int photoWall = 6;
  static const int me = 7;

  static const List<int> feedbackGroup = [intro, reviews, guestbook, photoWall];

  static bool isFeedbackGroup(int tabId) =>
      tabId >= intro && tabId <= photoWall;

  /// `IndexedStack` 里的页面顺序：介绍组始终只占 FeedbackPage 一个位置。
  static List<int> bodyOrder({required bool queueEnabled}) => [
    if (queueEnabled) queue,
    booking,
    schedule,
    intro,
    me,
  ];

  /// 导航项顺序：宽屏时介绍组展开成四项。
  static List<int> destinationOrder({
    required bool queueEnabled,
    required bool wide,
  }) => [
    if (queueEnabled) queue,
    booking,
    schedule,
    if (wide) ...feedbackGroup else intro,
    me,
  ];

  static int bodyIndex({required int tabId, required bool queueEnabled}) {
    final target = isFeedbackGroup(tabId) ? intro : tabId;
    final index = bodyOrder(queueEnabled: queueEnabled).indexOf(target);
    return index < 0 ? 0 : index;
  }

  /// 当前应该高亮的导航项下标。
  static int destinationIndex({
    required int tabId,
    required int feedbackSegment,
    required bool queueEnabled,
    required bool wide,
  }) {
    final target = wide
        ? (isFeedbackGroup(tabId) ? intro + feedbackSegment : tabId)
        : (isFeedbackGroup(tabId) ? intro : tabId);
    final index = destinationOrder(
      queueEnabled: queueEnabled,
      wide: wide,
    ).indexOf(target);
    return index < 0 ? 0 : index;
  }
}
