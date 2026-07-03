import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../app_shell.dart';
import '../services/photo_wall_service.dart';
import '../widgets/main_app_bar.dart';

class PhotoWallPage extends StatefulWidget {
  const PhotoWallPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<PhotoWallPage> createState() => PhotoWallPageState();
}

class PhotoWallPageState extends State<PhotoWallPage> {
  final ScrollController _scrollController = ScrollController();
  late final VoidCallback _tabReselectListener;

  bool _loading = true;
  String? _error;
  List<PhotoWallPageItem> _pages = const [];
  Map<int, List<PhotoWallPhotoItem>> _photosByPageId = const {};
  int? _selectedPageId;

  @override
  void initState() {
    super.initState();
    _tabReselectListener = () {
      final event = AppShell.tabReselectNotifier.value;
      if (event == null || event.index != AppShell.feedbackTabIndex()) return;
      _handleTabReselect(event.action);
    };
    if (!widget.embedded) {
      AppShell.tabReselectNotifier.addListener(_tabReselectListener);
    }
    _loadData();
  }

  @override
  void dispose() {
    if (!widget.embedded) {
      AppShell.tabReselectNotifier.removeListener(_tabReselectListener);
    }
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> scrollToTop() async {
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> refreshData() => _loadData(forceRefresh: true);

  Future<void> _handleTabReselect(TabReselectAction action) async {
    if (action == TabReselectAction.scrollToTop) {
      await scrollToTop();
      return;
    }
    await _loadData(forceRefresh: true);
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (!mounted) return;

    try {
      if (!forceRefresh) {
        setState(() {
          _loading = true;
          _error = null;
        });
      } else {
        setState(() {
          _error = null;
        });
      }

      final snapshot = await PhotoWallService.fetchSnapshot();
      if (!mounted) return;

      final nextPages = snapshot.pages;
      final selectedStillExists = nextPages.any(
        (page) => page.id == _selectedPageId,
      );
      setState(() {
        _pages = nextPages;
        _photosByPageId = snapshot.photosByPageId;
        _selectedPageId = selectedStillExists
            ? _selectedPageId
            : (nextPages.isEmpty ? null : nextPages.first.id);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  int _columnCount(double width) {
    if (width >= 1400) return 5;
    if (width >= 1100) return 4;
    if (width >= 760) return 3;
    if (width >= 520) return 2;
    return 1;
  }

  List<PhotoWallPhotoItem> get _selectedPhotos {
    final selectedPageId = _selectedPageId;
    if (selectedPageId == null) return const [];
    return _photosByPageId[selectedPageId] ?? const [];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildBody();
    }

    return Scaffold(
      appBar: MainAppBar(title: const Text('照片墙')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('请求失败: $_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _loadData(forceRefresh: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_pages.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadData(forceRefresh: true),
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 220),
            Center(child: Text('暂无照片墙数据')),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildPageSelector(),
        Expanded(
          child: _selectedPhotos.isEmpty
              ? RefreshIndicator(
                  onRefresh: () => _loadData(forceRefresh: true),
                  child: ListView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    children: const [
                      SizedBox(height: 160),
                      Center(child: Text('当前页面暂无照片')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadData(forceRefresh: true),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final count = _columnCount(constraints.maxWidth);
                      return MasonryGridView.builder(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
                        gridDelegate:
                            SliverSimpleGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: count,
                            ),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        itemCount: _selectedPhotos.length,
                        itemBuilder: (context, index) =>
                            _buildPhotoCard(_selectedPhotos[index]),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildPageSelector() {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF312837) : const Color(0xFFF0DCEB),
          ),
        ),
      ),
      child: SizedBox(
        height: 42,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _pages.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final page = _pages[index];
            final selected = page.id == _selectedPageId;
            return ChoiceChip(
              label: Text(page.displayLabel),
              selected: selected,
              onSelected: (_) {
                if (selected) return;
                setState(() => _selectedPageId = page.id);
                unawaited(scrollToTop());
              },
              labelStyle: TextStyle(
                color: selected
                    ? colorScheme.onPrimary
                    : (isDark
                          ? const Color(0xFFEDE5F3)
                          : const Color(0xFF5E536C)),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              selectedColor: const Color(0xFFFF5DAF),
              backgroundColor: isDark
                  ? const Color(0xFF241F29)
                  : const Color(0xFFF8EEF4),
              side: BorderSide(
                color: selected
                    ? const Color(0xFFFF5DAF)
                    : (isDark
                          ? const Color(0xFF3A3140)
                          : const Color(0xFFF0DCEB)),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPhotoCard(PhotoWallPhotoItem photo) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF322A39)
        : const Color(0xFFF0DCEB);
    final captionColor = const Color(0xFFFF5DAF);
    final badgeBg = isDark ? const Color(0xFF35273A) : const Color(0xFFFFEDF5);
    final badgeTextColor = isDark
        ? const Color(0xFFF8D9E8)
        : const Color(0xFFC04C88);
    final imageBg = isDark ? const Color(0xFF2B2530) : const Color(0xFFF7F0F6);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (photo.caption.isNotEmpty) ...[
              Text(
                photo.caption,
                style: TextStyle(
                  color: captionColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (photo.hasBadge) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      photo.badge,
                      style: TextStyle(
                        color: badgeTextColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                color: imageBg,
                child: CachedNetworkImage(
                  imageUrl: photo.url,
                  fit: BoxFit.fitWidth,
                  placeholder: (context, url) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Color(0xFF8B8399),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
