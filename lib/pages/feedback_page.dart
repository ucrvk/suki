import 'package:flutter/material.dart';

import '../app_shell.dart';
import '../widgets/main_app_bar.dart';
import 'guestbook_page.dart';
import 'reviews_page.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  int _segment = 0; // 0=评价, 1=留言
  final GlobalKey<ReviewsPageState> _reviewsKey = GlobalKey<ReviewsPageState>();
  final GlobalKey<GuestbookPageState> _guestbookKey = GlobalKey<GuestbookPageState>();
  late final VoidCallback _tabReselectListener;

  @override
  void initState() {
    super.initState();
    _tabReselectListener = () {
      final event = AppShell.tabReselectNotifier.value;
      if (event == null || event.index != 2) return;
      _handleTabReselect(event.action);
    };
    AppShell.tabReselectNotifier.addListener(_tabReselectListener);
  }

  @override
  void dispose() {
    AppShell.tabReselectNotifier.removeListener(_tabReselectListener);
    super.dispose();
  }

  Future<void> _handleTabReselect(TabReselectAction action) async {
    if (_segment == 0) {
      if (action == TabReselectAction.scrollToTop) {
        await _reviewsKey.currentState?.scrollToTop();
      } else {
        await _reviewsKey.currentState?.refreshData();
      }
      return;
    }
    if (action == TabReselectAction.scrollToTop) {
      await _guestbookKey.currentState?.scrollToTop();
    } else {
      await _guestbookKey.currentState?.refreshData();
    }
  }

  Future<void> _onFabTap() async {
    if (_segment == 0) {
      await _reviewsKey.currentState?.showSubmitSheet();
    } else {
      await _guestbookKey.currentState?.showSubmitSheet();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MainAppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('评价'),
            const SizedBox(width: 10),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(value: 0, label: Text('评价')),
                ButtonSegment<int>(value: 1, label: Text('留言')),
              ],
              selected: {_segment},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                final next = selection.first;
                if (next == _segment) return;
                setState(() => _segment = next);
              },
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _segment,
        children: [
          ReviewsPage(key: _reviewsKey, embedded: true),
          GuestbookPage(key: _guestbookKey, embedded: true),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onFabTap,
        icon: Icon(_segment == 0 ? Icons.rate_review_outlined : Icons.edit_note_rounded),
        label: Text(_segment == 0 ? '写评价' : '写留言'),
      ),
    );
  }
}

