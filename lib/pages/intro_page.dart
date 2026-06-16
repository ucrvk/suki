import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_shell.dart';
import '../services/intro_profile_service.dart';
import '../widgets/main_app_bar.dart';

class IntroPage extends StatefulWidget {
  const IntroPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<IntroPage> createState() => IntroPageState();
}

class IntroPageState extends State<IntroPage> {
  bool _loading = true;
  String? _error;
  List<IntroProfileRecord> _records = const [];
  final ScrollController _scrollController = ScrollController();
  late final VoidCallback _tabReselectListener;

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
    if (_scrollController.hasClients &&
        _scrollController.position.hasContentDimensions) {
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
        final cached = await IntroProfileService.loadCachedProfiles();
        if (cached != null) {
          if (!mounted) return;
          setState(() {
            _records = cached;
            _loading = false;
            _error = null;
          });
          unawaited(_refreshDataInBackground());
          return;
        }
      }

      setState(() {
        _loading = true;
        _error = null;
      });

      final records = forceRefresh
          ? await IntroProfileService.refreshProfiles()
          : await IntroProfileService.getProfiles(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _records = records;
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

  Future<void> _refreshDataInBackground() async {
    try {
      final records = await IntroProfileService.refreshProfiles();
      if (!mounted) return;
      setState(() {
        _records = records;
      });
    } catch (_) {
      // Keep the cached profiles if refresh fails.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildBody();
    }

    return Scaffold(
      appBar: MainAppBar(title: const Text('介绍')),
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

    if (_records.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadData(forceRefresh: true),
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 220),
            Center(child: Text('暂无介绍数据')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(forceRefresh: true),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        itemCount: _records.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _buildProfileCard(_records[index]),
      ),
    );
  }

  Widget _buildProfileCard(IntroProfileRecord record) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF3A3250);
    final bodyColor = isDark ? const Color(0xFFEDE5F3) : const Color(0xFF5E536C);
    final mutedColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7D7178);
    final statBg = isDark ? const Color(0xFF2B2530) : const Color(0xFFF7ECF5);
    final actionBg = isDark ? const Color(0xFF2A2230) : const Color(0xFFF9EEF4);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF322A39) : const Color(0xFFF0DCEB),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(record.avatarUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      record.username,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: titleColor,
                      ),
                    ),
                    _buildStatPill('HP ${record.statHp}', statBg, mutedColor),
                    _buildStatPill('ATK ${record.statAtk}', statBg, mutedColor),
                    _buildStatPill('DEF ${record.statDef}', statBg, mutedColor),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  record.shortBio,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: bodyColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 84,
            child: FilledButton.tonal(
              onPressed: () => _showDetailSheet(record),
              style: FilledButton.styleFrom(
                backgroundColor: actionBg,
                foregroundColor: titleColor,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.open_in_new_rounded, size: 20),
                  SizedBox(height: 8),
                  Text(
                    '查看详情',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill(String text, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildAvatar(String avatarUrl) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fallbackBg = isDark ? const Color(0xFF2B2530) : const Color(0xFFF4E5EF);
    return SizedBox(
      width: 84,
      height: 84,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          color: fallbackBg,
          child: avatarUrl.isEmpty
              ? const Center(
                  child: Icon(
                    Icons.person_outline,
                    color: Color(0xFF8B8399),
                  ),
                )
              : CachedNetworkImage(
                  imageUrl: avatarUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (context, url, error) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Color(0xFF8B8399),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _showDetailSheet(IntroProfileRecord record) async {
    final imageUrls = <String>{
      record.illustrationUrl,
      record.extraImage1Url,
      record.extraImage2Url,
    }.where((url) => url.trim().isNotEmpty).toList();
    final pageController = PageController(
      viewportFraction: imageUrls.length > 1 ? 0.92 : 1.0,
    );
    var currentPage = 0;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
          final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
          final bodyColor = isDark ? const Color(0xFFEDE5F3) : const Color(0xFF5E536C);
          final mutedColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7D7178);

          return StatefulBuilder(
            builder: (context, setSheetState) {
              Future<void> goToPage(int nextPage) async {
                if (nextPage < 0 || nextPage >= imageUrls.length) return;
                if (!pageController.hasClients) return;
                await pageController.animateToPage(
                  nextPage,
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                );
              }

              return SafeArea(
                child: FractionallySizedBox(
                  heightFactor: 0.92,
                  child: Material(
                    color: cardBg,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 920;
                        final imagePane = _buildDetailImagePane(
                          imageUrls: imageUrls,
                          isDark: isDark,
                          mutedColor: mutedColor,
                          pageController: pageController,
                          currentPage: currentPage,
                          onPageChanged: (index) {
                            setSheetState(() => currentPage = index);
                          },
                          onPrevious: currentPage > 0 ? () => goToPage(currentPage - 1) : null,
                          onNext: currentPage < imageUrls.length - 1
                              ? () => goToPage(currentPage + 1)
                              : null,
                        );
                        final detailPane = _buildDetailTextPane(
                          record: record,
                          bodyColor: bodyColor,
                          mutedColor: mutedColor,
                          isDark: isDark,
                        );

                        if (isWide) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(flex: 11, child: imagePane),
                                const SizedBox(width: 16),
                                Expanded(flex: 9, child: detailPane),
                              ],
                            ),
                          );
                        }

                        return ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                            imagePane,
                            const SizedBox(height: 14),
                            detailPane,
                          ],
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      pageController.dispose();
    }
  }

  Widget _buildDetailImageCard({
    required String imageUrl,
    required bool isDark,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (context, url, error) => _buildDetailImageFallback(isDark),
      ),
    );
  }

  Widget _buildDetailImagePane({
    required List<String> imageUrls,
    required bool isDark,
    required Color mutedColor,
    required PageController pageController,
    required int currentPage,
    required ValueChanged<int> onPageChanged,
    required VoidCallback? onPrevious,
    required VoidCallback? onNext,
  }) {
    final hasMultipleImages = imageUrls.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            children: [
              if (imageUrls.isEmpty)
                _buildDetailImageFallback(isDark)
              else
                PageView.builder(
                  controller: pageController,
                  padEnds: false,
                  onPageChanged: onPageChanged,
                  itemCount: imageUrls.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: EdgeInsets.only(
                        right: index == imageUrls.length - 1 ? 0 : 10,
                      ),
                      child: _buildDetailImageCard(
                        imageUrl: imageUrls[index],
                        isDark: isDark,
                      ),
                    );
                  },
                ),
              if (hasMultipleImages)
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildCarouselButton(
                          icon: Icons.chevron_left_rounded,
                          onPressed: onPrevious,
                          isDark: isDark,
                        ),
                        _buildCarouselButton(
                          icon: Icons.chevron_right_rounded,
                          onPressed: onNext,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (hasMultipleImages) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '左右滑动查看',
                style: TextStyle(fontSize: 12, color: mutedColor),
              ),
              const Spacer(),
              Text(
                '${currentPage + 1}/${imageUrls.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: mutedColor,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDetailTextPane({
    required IntroProfileRecord record,
    required Color bodyColor,
    required Color mutedColor,
    required bool isDark,
  }) {
    final statBg = isDark ? const Color(0xFF2B2530) : const Color(0xFFF7ECF5);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            record.username,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStatPill('HP ${record.statHp}', statBg, mutedColor),
              _buildStatPill('ATK ${record.statAtk}', statBg, mutedColor),
              _buildStatPill('DEF ${record.statDef}', statBg, mutedColor),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            record.fullBio.isEmpty ? '暂无详细介绍' : record.fullBio,
            style: TextStyle(
              fontSize: 15,
              height: 1.55,
              color: bodyColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarouselButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required bool isDark,
  }) {
    final background = isDark ? const Color(0xCC1F1B24) : const Color(0xCCFFFFFF);
    final disabledBackground = isDark ? const Color(0x662B2530) : const Color(0x66F7ECF5);
    final foreground = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF5A5056);

    return Material(
      color: onPressed == null ? disabledBackground : background,
      shape: const CircleBorder(),
      elevation: 1,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: foreground),
        splashRadius: 20,
        tooltip: onPressed == null ? null : '切换图片',
      ),
    );
  }

  Widget _buildDetailImageFallback(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2B2530) : const Color(0xFFF3E7F0),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child: Icon(Icons.image_outlined, color: Color(0xFF8B8399), size: 36),
      ),
    );
  }
}
