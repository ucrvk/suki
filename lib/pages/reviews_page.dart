import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_shell.dart';
import '../services/maid_catalog_cache_service.dart';
import '../services/supabase_service.dart';
import '../widgets/main_app_bar.dart';

class MaidOption {
  const MaidOption({
    required this.vrcid,
    required this.name,
  });

  final String vrcid;
  final String name;
}

class ReviewItem {
  const ReviewItem({
    required this.id,
    required this.maidVrcid,
    required this.maidName,
    required this.guestUsername,
    required this.liked,
    required this.comments,
    required this.createdAt,
    required this.maidImage,
  });

  final String id;
  final String maidVrcid;
  final String maidName;
  final String guestUsername;
  final bool liked;
  final List<String> comments;
  final DateTime createdAt;
  final String maidImage;
}

class MaidReviewGroup {
  const MaidReviewGroup({
    required this.maidVrcid,
    required this.maidName,
    required this.maidImage,
    required this.likeCount,
    required this.reviewCount,
    required this.latestAt,
    required this.reviews,
  });

  final String maidVrcid;
  final String maidName;
  final String maidImage;
  final int likeCount;
  final int reviewCount;
  final DateTime latestAt;
  final List<ReviewItem> reviews;
}

class ReviewsPage extends StatefulWidget {
  const ReviewsPage({super.key});

  @override
  State<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends State<ReviewsPage> {
  bool _loading = true;
  bool _submittingReview = false;
  String? _error;
  List<Map<String, dynamic>> _rawReviews = const [];
  List<MaidReviewGroup> _groups = const [];
  List<MaidOption> _maidOptions = const [];
  List<String> _presetComments = const [];
  int? _maxReviewsPerUser;
  final ScrollController _scrollController = ScrollController();
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
    _fetchReviews();
  }

  @override
  void dispose() {
    AppShell.tabReselectNotifier.removeListener(_tabReselectListener);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleTabReselect(TabReselectAction action) async {
    if (action == TabReselectAction.scrollToTop) {
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }
    await _fetchReviews(forceRefresh: true);
  }

  Future<void> _fetchReviews({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final raw = await SupabaseService.client.from('suki_reviews').select('*');
      final config = await SupabaseService.client.from('suki_review_config').select('*').limit(1);
      final snapshot = await MaidCatalogCacheService.getSnapshot(forceRefresh: forceRefresh);

      final firstConfig = config.isNotEmpty ? Map<String, dynamic>.from(config.first) : null;
      final presetComments = ((firstConfig?['preset_comments'] as List?) ?? const [])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final maxReviewsPerUser = firstConfig?['max_reviews_per_user'] is num
          ? (firstConfig!['max_reviews_per_user'] as num).toInt()
          : null;

      final hiddenMaidVrcids = snapshot.hiddenMaidVrcids;
      final maidImageByVrcid = snapshot.maidImageByVrcid;

      final maidOptions = <MaidOption>[];
      for (final maid in snapshot.maids) {
        final vrcid = (maid['vrcid'] ?? '').toString().trim();
        final name = (maid['name'] ?? '').toString().trim();
        if (vrcid.isEmpty) continue;
        if (!hiddenMaidVrcids.contains(vrcid) && name.isNotEmpty) {
          maidOptions.add(MaidOption(vrcid: vrcid, name: name));
        }
      }
      maidOptions.sort((a, b) => a.name.compareTo(b.name));

      final parsedRaw = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((row) {
            final maidVrcid = (row['maid_vrcid'] ?? '').toString().trim();
            return !hiddenMaidVrcids.contains(maidVrcid);
          })
          .toList();

      final groups = _buildGroups(parsedRaw, maidImageByVrcid);

      if (!mounted) return;
      setState(() {
        _rawReviews = parsedRaw;
        _groups = groups;
        _maidOptions = maidOptions;
        _presetComments = presetComments;
        _maxReviewsPerUser = maxReviewsPerUser;
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

  List<MaidReviewGroup> _buildGroups(
    List<Map<String, dynamic>> rawReviews,
    Map<String, String> maidImageByVrcid,
  ) {
    final grouped = <String, List<ReviewItem>>{};

    for (final row in rawReviews) {
      final maidVrcid = (row['maid_vrcid'] ?? '').toString().trim();
      if (maidVrcid.isEmpty) continue;

      final review = ReviewItem(
        id: (row['id'] ?? '').toString(),
        maidVrcid: maidVrcid,
        maidName: (row['maid_name'] ?? '').toString().trim(),
        guestUsername: (row['guest_username'] ?? '匿名用户').toString().trim(),
        liked: row['liked'] == true,
        comments: ((row['comments'] as List?) ?? const [])
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        createdAt: _parseCreatedAt(row['created_at']),
        maidImage: maidImageByVrcid[maidVrcid] ?? '',
      );

      grouped.putIfAbsent(maidVrcid, () => <ReviewItem>[]).add(review);
    }

    final groups = <MaidReviewGroup>[];

    for (final entry in grouped.entries) {
      final reviews = entry.value.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final likeCount = reviews.where((r) => r.liked).length;
      final reviewCount = reviews.length;
      final latestAt = reviews.first.createdAt;
      final maidName = reviews.first.maidName.isEmpty ? entry.key : reviews.first.maidName;

      groups.add(
        MaidReviewGroup(
          maidVrcid: entry.key,
          maidName: maidName,
          maidImage: maidImageByVrcid[entry.key] ?? '',
          likeCount: likeCount,
          reviewCount: reviewCount,
          latestAt: latestAt,
          reviews: reviews,
        ),
      );
    }

    groups.sort((a, b) {
      final byLikes = b.likeCount.compareTo(a.likeCount);
      if (byLikes != 0) return byLikes;

      final byReviews = b.reviewCount.compareTo(a.reviewCount);
      if (byReviews != 0) return byReviews;

      return b.latestAt.compareTo(a.latestAt);
    });

    return groups;
  }

  DateTime _parseCreatedAt(dynamic value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch((value * 1000).round());
    }
    final parsed = num.tryParse((value ?? '').toString());
    if (parsed == null) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.fromMillisecondsSinceEpoch((parsed * 1000).round());
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  int _columnCount(double width) {
    if (width >= 1400) return 5;
    if (width >= 1100) return 4;
    if (width >= 760) return 3;
    if (width >= 520) return 2;
    return 1;
  }

  Widget _buildReviewLine(ReviewItem review, String comment) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? const Color(0xFFEDE5F3) : const Color(0xFF5D556A);
    final secondaryText = isDark ? const Color(0xFFB6AABF) : const Color(0xFF8B8399);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              '$comment —— ${review.guestUsername}',
              style: TextStyle(
                color: primaryText,
                fontSize: 15,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatTime(review.createdAt),
            style: TextStyle(fontSize: 12, color: secondaryText),
          ),
          if (review.liked) ...[
            const SizedBox(width: 8),
            const Icon(
              Icons.thumb_up_alt_rounded,
              size: 14,
              color: Color(0xFFFF5DAF),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupCard(MaidReviewGroup group) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF3A3250);
    final metaColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7C748A);
    final emptyColor = isDark ? const Color(0xFF9A8FA4) : const Color(0xFF8B8399);
    final imageBg = isDark ? const Color(0xFF2B2530) : const Color(0xFFECDCF2);
    final reviewLines = <Widget>[];
    for (final review in group.reviews) {
      for (final comment in review.comments) {
        if (comment.isEmpty) continue;
        reviewLines.add(_buildReviewLine(review, comment));
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: imageBg,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: group.maidImage.isEmpty
                  ? const Center(
                      child: Icon(Icons.image_not_supported_outlined, color: Color(0xFF8B8399)),
                    )
                  : CachedNetworkImage(
                      imageUrl: group.maidImage,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (context, url) => const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (context, url, error) => const Center(
                        child: Icon(Icons.broken_image_outlined, color: Color(0xFF8B8399)),
                      ),
                    ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  group.maidName,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                    fontSize: 18,
                  ),
                ),
              ),
              RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 13, color: metaColor),
                  children: [
                    const TextSpan(text: '点赞 '),
                    TextSpan(
                      text: '${group.likeCount}',
                      style: const TextStyle(color: Color(0xFFFF5DAF), fontWeight: FontWeight.w800),
                    ),
                    const TextSpan(text: '  评价 '),
                    TextSpan(
                      text: '${group.reviewCount}',
                      style: const TextStyle(color: Color(0xFFFF5DAF), fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (reviewLines.isEmpty)
            Text('暂无可展示评论', style: TextStyle(color: emptyColor))
          else
            ...reviewLines,
        ],
      ),
    );
  }

  Future<void> _showSubmitReviewSheet() async {
    if (_maidOptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无可评价女仆')));
      return;
    }
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录后再评价')));
      return;
    }

    MaidOption selectedMaid = _maidOptions.first;
    bool liked = true;
    final selectedComments = <String>{};

    final shouldSubmit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '提交评价',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (_maxReviewsPerUser != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '每人最多 ${_maxReviewsPerUser!} 条评价',
                          style: const TextStyle(color: Color(0xFF7A7188), fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedMaid.vrcid,
                        decoration: const InputDecoration(labelText: '选择女仆'),
                        items: _maidOptions
                            .map((m) => DropdownMenuItem<String>(
                                  value: m.vrcid,
                                  child: Text(m.name),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          final found = _maidOptions.where((m) => m.vrcid == value).toList();
                          if (found.isEmpty) return;
                          setSheetState(() => selectedMaid = found.first);
                        },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: liked,
                        onChanged: (v) => setSheetState(() => liked = v),
                        title: const Text('点赞'),
                      ),
                      const SizedBox(height: 8),
                      const Text('选择评论（可多选）', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _presetComments
                            .map(
                              (c) => FilterChip(
                                label: Text(c),
                                selected: selectedComments.contains(c),
                                onSelected: (selected) {
                                  setSheetState(() {
                                    if (selected) {
                                      selectedComments.add(c);
                                    } else {
                                      selectedComments.remove(c);
                                    }
                                  });
                                },
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.of(sheetContext).pop(true),
                          child: const Text('提交评价'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (shouldSubmit != true) return;

    setState(() => _submittingReview = true);
    try {
      await SupabaseService.client.rpc(
        'submit_review',
        params: {
          'p_maid_vrcid': selectedMaid.vrcid,
          'p_maid_name': selectedMaid.name,
          'p_liked': liked,
          'p_comments': selectedComments.toList(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('评价提交成功')));
      MaidCatalogCacheService.invalidate();
      await _fetchReviews(forceRefresh: true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() => _submittingReview = false);
      } else {
        _submittingReview = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MainAppBar(
        title: Text('评价 (${_rawReviews.length})'),
      ),
      body: _buildBody(),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _submittingReview ? null : _showSubmitReviewSheet,
              icon: _submittingReview
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.rate_review_outlined),
              label: Text(_submittingReview ? '提交中' : '写评价'),
            ),
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
              FilledButton(onPressed: () => _fetchReviews(forceRefresh: true), child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    if (_groups.isEmpty) {
      return const Center(child: Text('暂无评价数据'));
    }

    return RefreshIndicator(
      onRefresh: () => _fetchReviews(forceRefresh: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = _columnCount(constraints.maxWidth);

          return MasonryGridView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
            gridDelegate: SliverSimpleGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: count,
            ),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            itemCount: _groups.length,
            itemBuilder: (context, index) => _buildGroupCard(_groups[index]),
          );
        },
      ),
    );
  }
}

