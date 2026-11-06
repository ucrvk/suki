import 'package:flutter/material.dart';

import '../app_shell.dart';
import '../widgets/main_app_bar.dart';
import '../widgets/responsive_shell.dart';
import 'guestbook_page.dart';
import 'intro_page.dart';
import 'photo_wall_page.dart';
import 'reviews_page.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key, this.segment = 0, this.onSegmentChanged});

  /// 当前分段（0 介绍，1 评价，2 留言，3 照片墙）。
  ///
  /// 宽屏左侧导航栏会直接控制这个值；窄屏由页面内的分段按钮控制，
  /// 并通过 [onSegmentChanged] 同步回外壳。
  final int segment;
  final ValueChanged<int>? onSegmentChanged;

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  int _segment = 0;
  final GlobalKey<IntroPageState> _introKey = GlobalKey<IntroPageState>();
  final GlobalKey<ReviewsPageState> _reviewsKey = GlobalKey<ReviewsPageState>();
  final GlobalKey<GuestbookPageState> _guestbookKey =
      GlobalKey<GuestbookPageState>();
  final GlobalKey<PhotoWallPageState> _photoWallKey =
      GlobalKey<PhotoWallPageState>();
  late final VoidCallback _tabReselectListener;

  @override
  void initState() {
    super.initState();
    _segment = widget.segment;
    _tabReselectListener = () {
      final event = AppShell.tabReselectNotifier.value;
      if (event == null) return;
      // 窄屏事件是组 ID（intro），宽屏是具体子项 ID（intro + segment）。
      if (event.index != AppShell.feedbackTabIndex() &&
          event.index != AppShell.introTabIndex() + _segment) {
        return;
      }
      _handleTabReselect(event.action);
    };
    AppShell.tabReselectNotifier.addListener(_tabReselectListener);
  }

  @override
  void didUpdateWidget(covariant FeedbackPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.segment != _segment) {
      // didUpdateWidget 之后必然紧跟 build，这里直接同步即可。
      _segment = widget.segment;
    }
  }

  @override
  void dispose() {
    AppShell.tabReselectNotifier.removeListener(_tabReselectListener);
    super.dispose();
  }

  Future<void> _handleTabReselect(TabReselectAction action) async {
    if (_segment == 0) {
      if (action == TabReselectAction.scrollToTop) {
        await _introKey.currentState?.scrollToTop();
      } else {
        await _introKey.currentState?.refreshData();
      }
      return;
    }

    if (_segment == 1) {
      if (action == TabReselectAction.scrollToTop) {
        await _reviewsKey.currentState?.scrollToTop();
      } else {
        await _reviewsKey.currentState?.refreshData();
      }
      return;
    }

    if (_segment == 2) {
      if (action == TabReselectAction.scrollToTop) {
        await _guestbookKey.currentState?.scrollToTop();
      } else {
        await _guestbookKey.currentState?.refreshData();
      }
      return;
    }

    if (action == TabReselectAction.scrollToTop) {
      await _photoWallKey.currentState?.scrollToTop();
    } else {
      await _photoWallKey.currentState?.refreshData();
    }
  }

  Future<void> _onFabTap() async {
    if (_segment == 1) {
      await _reviewsKey.currentState?.showSubmitSheet();
    } else if (_segment == 2) {
      await _guestbookKey.currentState?.showSubmitSheet();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = ShellScope.isWide(context);
    return Scaffold(
      // 宽屏左栏直接提供四个入口，顶栏（分段按钮）不再需要。
      appBar: wide
          ? null
          : MainAppBar(
              title: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment<int>(value: 0, label: Text('介绍')),
                    ButtonSegment<int>(value: 1, label: Text('评价')),
                    ButtonSegment<int>(value: 2, label: Text('留言')),
                    ButtonSegment<int>(value: 3, label: Text('照片墙')),
                  ],
                  selected: {_segment},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    final next = selection.first;
                    if (next == _segment) return;
                    setState(() => _segment = next);
                    widget.onSegmentChanged?.call(next);
                  },
                ),
              ),
            ),
      body: IndexedStack(
        index: _segment,
        children: [
          IntroPage(key: _introKey, embedded: true),
          ReviewsPage(key: _reviewsKey, embedded: true),
          GuestbookPage(key: _guestbookKey, embedded: true),
          PhotoWallPage(key: _photoWallKey, embedded: true),
        ],
      ),
      floatingActionButton: _segment == 0 || _segment == 3
          ? null
          : FloatingActionButton.extended(
              onPressed: _onFabTap,
              icon: Icon(
                _segment == 1
                    ? Icons.rate_review_outlined
                    : Icons.edit_note_rounded,
              ),
              label: Text(_segment == 1 ? '写评价' : '写留言'),
            ),
    );
  }
}
