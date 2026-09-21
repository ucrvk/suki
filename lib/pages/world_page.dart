import 'dart:async';

import 'package:flutter/material.dart';

import '../models/world_content_entry.dart';
import '../services/account_service.dart';
import '../services/ending_unlock_service.dart';
import '../services/spoiler_mode_store.dart';
import '../services/world_content_service.dart';
import '../theme/app_colors.dart';

enum WorldSection { witch, lore, endings }

abstract interface class WorldDataSource {
  Future<WorldContentSnapshot?> loadCachedCodex();
  Future<WorldContentSnapshot?> loadCachedEndings();
  Future<WorldContentSnapshot> refreshCodex();
  Future<WorldContentSnapshot> refreshEndings();
}

class RepositoryWorldDataSource implements WorldDataSource {
  RepositoryWorldDataSource([WorldContentRepository? repository])
    : _repository = repository ?? WorldContentRepository();

  final WorldContentRepository _repository;

  @override
  Future<WorldContentSnapshot?> loadCachedCodex() =>
      _repository.loadCachedCodex();

  @override
  Future<WorldContentSnapshot?> loadCachedEndings() =>
      _repository.loadCachedEndings();

  @override
  Future<WorldContentSnapshot> refreshCodex() => _repository.refreshCodex();

  @override
  Future<WorldContentSnapshot> refreshEndings() => _repository.refreshEndings();
}

class WorldPageController {
  VoidCallback? _scrollToTop;
  VoidCallback? _refresh;

  void scrollToTop() => _scrollToTop?.call();
  void refresh() => _refresh?.call();
}

class WorldPage extends StatefulWidget {
  const WorldPage({
    super.key,
    this.controller,
    this.dataSource,
    this.spoilerModeStore,
    this.unlockRepository,
    this.authService,
  });

  final WorldPageController? controller;
  final WorldDataSource? dataSource;
  final SpoilerModeStore? spoilerModeStore;
  final EndingUnlockRepository? unlockRepository;
  final AccountAuthService? authService;

  @override
  State<WorldPage> createState() => _WorldPageState();
}

class _WorldPageState extends State<WorldPage>
    with SingleTickerProviderStateMixin {

  late final TabController _tabController;
  late final WorldDataSource _dataSource;
  final _scrollControllers = {
    for (final section in WorldSection.values) section: ScrollController(),
  };

  SpoilerModeStore? _spoilerStore;
  EndingUnlockRepository? _unlockRepository;
  AccountAuthService? _authService;
  StreamSubscription<AccountIdentity?>? _authSubscription;
  bool _spoilerEnabled = true;
  String? _userId;
  Set<String> _unlockedIds = const <String>{};
  bool _unlocksLoading = false;
  Object? _unlocksError;

  WorldContentSnapshot? _codexSnapshot;
  WorldContentSnapshot? _endingsSnapshot;
  Object? _codexError;
  Object? _endingsError;
  bool _codexLoading = true;
  bool _endingsLoading = true;
  bool _codexRefreshing = false;
  bool _endingsRefreshing = false;
  WorldSection _section = WorldSection.witch;

  List<WorldContentEntry> get _visibleEndings {
    final entries = _endingsSnapshot?.entries ?? const <WorldContentEntry>[];
    // 未登录时无法判断解锁状态，交给结局页的登录提示处理。
    if (!_spoilerEnabled && _userId == null) return const <WorldContentEntry>[];
    // 剧透模式关闭时依旧列出全部结局，未解锁的以 ??? 占位。
    return entries;
  }

  bool _isLocked(WorldContentEntry entry) {
    if (_spoilerEnabled || _userId == null) return false;
    return !_unlockedIds.contains(entry.id);
  }

  @override
  void initState() {
    super.initState();
    _dataSource = widget.dataSource ?? RepositoryWorldDataSource();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(_handleTabChanged);
    widget.controller?._scrollToTop = _scrollToTop;
    widget.controller?._refresh = () => unawaited(_refreshCurrent());
    _spoilerStore = widget.spoilerModeStore;
    if (_spoilerStore != null) {
      _spoilerEnabled = _spoilerStore!.value;
      _spoilerStore!.addListener(_handleSpoilerChanged);
      _unlockRepository =
          widget.unlockRepository ?? EndingUnlockRepository();
      _authService = widget.authService ?? SupabaseAccountAuthService();
      _userId = _authService!.currentAccount?.id;
      _authSubscription = _authService!.authChanges.listen(_applyAccount);
    }
    unawaited(_loadCodex());
    unawaited(_loadEndings());
    if (_userId != null) unawaited(_loadUnlockedIds());
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _spoilerStore?.removeListener(_handleSpoilerChanged);
    widget.controller?._scrollToTop = null;
    widget.controller?._refresh = null;
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _handleSpoilerChanged() {
    final enabled = _spoilerStore?.value ?? true;
    if (enabled == _spoilerEnabled) return;
    setState(() => _spoilerEnabled = enabled);
    if (_userId != null) unawaited(_loadUnlockedIds());
  }

  Future<void> _applyAccount(AccountIdentity? account) async {
    if (!mounted) return;
    final userId = account?.id;
    setState(() => _userId = userId);
    if (userId != null) await _loadUnlockedIds();
  }

  Future<void> _loadUnlockedIds({bool showFailure = false}) async {
    final repository = _unlockRepository;
    final userId = _userId;
    if (repository == null || userId == null) {
      if (!mounted) return;
      setState(() {
        _unlockedIds = const <String>{};
        _unlocksLoading = false;
      });
      return;
    }
    setState(() {
      _unlocksLoading = true;
      _unlocksError = null;
    });
    try {
      final cached = await repository.loadCached(userId);
      if (!mounted) return;
      setState(() => _unlockedIds = cached);
      final fresh = await repository.refresh(userId);
      if (!mounted) return;
      setState(() {
        _unlockedIds = fresh;
        _unlocksLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _unlocksLoading = false;
        if (_unlockedIds.isEmpty) _unlocksError = error;
      });
      if (_unlockedIds.isEmpty || !showFailure) return;
      _showRefreshFailure();
    }
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) return;
    final next = WorldSection.values[_tabController.index];
    if (next != _section) setState(() => _section = next);
  }

  Future<void> _loadCodex() async {
    try {
      final cached = await _dataSource.loadCachedCodex();
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          _codexSnapshot = cached;
          _codexLoading = false;
        });
        unawaited(_refreshCodex(showFailure: true));
        return;
      }
    } catch (_) {
      // A malformed cache falls through to the network.
    }
    await _refreshCodex(showFailure: false);
  }

  Future<void> _loadEndings() async {
    try {
      final cached = await _dataSource.loadCachedEndings();
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          _endingsSnapshot = cached;
          _endingsLoading = false;
        });
        unawaited(_refreshEndings(showFailure: true));
        return;
      }
    } catch (_) {
      // A malformed cache falls through to the network.
    }
    await _refreshEndings(showFailure: false);
  }

  Future<void> _refreshCodex({required bool showFailure}) async {
    if (_codexRefreshing) return;
    setState(() {
      _codexRefreshing = true;
      _codexError = null;
      if (_codexSnapshot == null) _codexLoading = true;
    });
    try {
      final snapshot = await _dataSource.refreshCodex();
      if (!mounted) return;
      setState(() {
        _codexSnapshot = snapshot;
        _codexLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (_codexSnapshot == null) {
        setState(() {
          _codexError = error;
          _codexLoading = false;
        });
      } else if (showFailure) {
        _showRefreshFailure();
      }
    } finally {
      if (mounted) setState(() => _codexRefreshing = false);
    }
  }

  Future<void> _refreshEndings({required bool showFailure}) async {
    if (_endingsRefreshing) return;
    setState(() {
      _endingsRefreshing = true;
      _endingsError = null;
      if (_endingsSnapshot == null) _endingsLoading = true;
    });
    try {
      final snapshot = await _dataSource.refreshEndings();
      if (!mounted) return;
      setState(() {
        _endingsSnapshot = snapshot;
        _endingsLoading = false;
      });
      if (_userId != null) await _loadUnlockedIds(showFailure: showFailure);
    } catch (error) {
      if (!mounted) return;
      if (_endingsSnapshot == null) {
        setState(() {
          _endingsError = error;
          _endingsLoading = false;
        });
      } else if (showFailure) {
        _showRefreshFailure();
      }
    } finally {
      if (mounted) setState(() => _endingsRefreshing = false);
    }
  }

  void _showRefreshFailure() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('刷新失败，已保留本地内容')));
  }

  Future<void> _refreshCurrent() {
    return _section == WorldSection.endings
        ? _refreshEndings(showFailure: true)
        : _refreshCodex(showFailure: true);
  }

  Future<void> _scrollToTop() async {
    final controller = _scrollControllers[_section]!;
    if (!controller.hasClients) return;
    await controller.animateTo(
      0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final refreshing = _section == WorldSection.endings
        ? _endingsRefreshing
        : _codexRefreshing;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '世界',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (refreshing)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            indicatorColor: AppColors.accent,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textMuted,
            dividerColor: AppColors.outline,
            tabs: const [
              Tab(text: '魔女图鉴'),
              Tab(text: '世界观'),
              Tab(text: '结局'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCodexSection(WorldContentKind.witch),
                _buildCodexSection(WorldContentKind.lore),
                _buildEndingsSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodexSection(WorldContentKind kind) {
    final section = kind == WorldContentKind.witch
        ? WorldSection.witch
        : WorldSection.lore;
    final entries = (_codexSnapshot?.entries ?? const <WorldContentEntry>[])
        .where((entry) => entry.kind == kind)
        .toList(growable: false);
    return _buildListState(
      section: section,
      loading: _codexLoading,
      error: _codexError,
      entries: entries,
      emptyText: kind == WorldContentKind.witch ? '暂无魔女图鉴' : '暂无世界观',
      onRefresh: () => _refreshCodex(showFailure: true),
      onRetry: () => _refreshCodex(showFailure: false),
    );
  }

  Widget _buildListState({
    required WorldSection section,
    required bool loading,
    required Object? error,
    required List<WorldContentEntry> entries,
    required String emptyText,
    required Future<void> Function() onRefresh,
    required VoidCallback onRetry,
  }) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return _WorldMessageState(
        icon: Icons.cloud_off_rounded,
        title: '内容加载失败',
        message: error.toString(),
        actionLabel: '重试',
        onAction: onRetry,
      );
    }
    if (entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          controller: _scrollControllers[section],
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 140),
            _WorldMessageState(
              icon: Icons.auto_stories_outlined,
              title: emptyText,
              message: '下拉即可重新获取',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        key: PageStorageKey<String>('world-${section.name}'),
        controller: _scrollControllers[section],
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, index) => _buildSummaryCard(entries[index]),
      ),
    );
  }

  Widget _buildEndingsSection() {
    if (_endingsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_endingsError != null) {
      return _WorldMessageState(
        icon: Icons.cloud_off_rounded,
        title: '结局加载失败',
        message: _endingsError.toString(),
        actionLabel: '重试',
        onAction: () => _refreshEndings(showFailure: false),
      );
    }
    final entries = _visibleEndings;
    if (!_spoilerEnabled) {
      if (_userId == null) {
        return _WorldMessageState(
          icon: Icons.lock_outline_rounded,
          title: '登录后查看已解锁结局',
          message: '剧透模式关闭时，只有登录后才能看到你已解锁的结局',
        );
      }
      if (_unlocksError != null && entries.isEmpty) {
        return _WorldMessageState(
          icon: Icons.cloud_off_rounded,
          title: '解锁状态加载失败',
          message: _unlocksError.toString(),
          actionLabel: '重试',
          onAction: () => _loadUnlockedIds(),
        );
      }
      if (_unlocksLoading && entries.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
    }

    final groups = groupEndingsByScript(entries);
    if (groups.isEmpty) {
      return _buildListState(
        section: WorldSection.endings,
        loading: false,
        error: null,
        entries: const [],
        emptyText: '暂无结局',
        onRefresh: () => _refreshEndings(showFailure: true),
        onRetry: () => _refreshEndings(showFailure: false),
      );
    }

    final showProgress = _userId != null;
    final children = <Widget>[];
    for (final group in groups.entries) {
      children.add(_buildGroupHeader(group, showProgress: showProgress));
      children.addAll(group.value.map(_buildEndingCard));
    }
    return RefreshIndicator(
      onRefresh: () => _refreshEndings(showFailure: true),
      child: ListView.separated(
        key: const PageStorageKey<String>('world-endings'),
        controller: _scrollControllers[WorldSection.endings],
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, index) => children[index],
      ),
    );
  }

  Widget _buildGroupHeader(
    MapEntry<String, List<WorldContentEntry>> group, {
    required bool showProgress,
  }) {
    final total = group.value.length;
    final unlocked = showProgress
        ? group.value.where((entry) => _unlockedIds.contains(entry.id)).length
        : null;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              group.key,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          if (unlocked != null)
            Text(
              '（$unlocked/$total）',
              style: TextStyle(
                color: unlocked == total
                    ? AppColors.accent
                    : AppColors.textMuted,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(WorldContentEntry entry) {
    return InkWell(
      key: ValueKey(entry.id),
      borderRadius: BorderRadius.circular(22),
      onTap: () => _showDetails(entry),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.outline),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WorldImage(url: entry.imageUrl, width: 88, height: 104),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (entry.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      entry.subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textMuted, height: 1.35),
                    ),
                  ],
                  if (entry.tags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _TagWrap(tags: entry.tags),
                  ],
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 6, top: 2),
              child: Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEndingCard(WorldContentEntry entry) {
    final locked = _isLocked(entry);
    return InkWell(
      key: ValueKey(entry.id),
      borderRadius: BorderRadius.circular(20),
      onTap: locked ? () => _showLockedHint() : () => _showDetails(entry),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: [
            Icon(
              locked ? Icons.lock_outline_rounded : Icons.visibility_outlined,
              color: locked ? AppColors.textMuted : AppColors.accent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    locked ? '???' : entry.title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: locked ? AppColors.textMuted : AppColors.textPrimary,
                    ),
                  ),
                  if (locked) ...[
                    const SizedBox(height: 5),
                    const Text(
                      '尚未解锁',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ] else if (entry.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      entry.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                  if (!locked && entry.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _TagWrap(tags: entry.tags),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  void _showLockedHint() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('该结局尚未解锁')));
  }

  Future<void> _showDetails(WorldContentEntry entry) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surfaceElevated,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.9,
        child: _WorldDetailSheet(entry: entry),
      ),
    );
  }
}

class _WorldDetailSheet extends StatefulWidget {
  const _WorldDetailSheet({required this.entry});

  final WorldContentEntry entry;

  @override
  State<_WorldDetailSheet> createState() => _WorldDetailSheetState();
}

class _WorldDetailSheetState extends State<_WorldDetailSheet> {
  final PageController _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final images = entry.imageUrls;
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          if (images.isNotEmpty) ...[
            SizedBox(
              height: 300,
              child: PageView.builder(
                controller: _pageController,
                itemCount: images.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (_, index) => Padding(
                  padding: EdgeInsets.only(
                    right: index + 1 < images.length ? 8 : 0,
                  ),
                  child: _WorldImage(
                    url: images[index],
                    width: double.infinity,
                    height: 300,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            if (images.length > 1) ...[
              const SizedBox(height: 8),
              Text(
                '${_page + 1}/${images.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ],
            const SizedBox(height: 18),
          ],
          if (entry.kind == WorldContentKind.ending)
            Text(
              entry.script,
              style: const TextStyle(color: AppColors.accent),
            ),
          Text(
            entry.title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          if (entry.subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              entry.subtitle,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 15,
                height: 1.45,
              ),
            ),
          ],
          if (entry.tags.isNotEmpty) ...[
            const SizedBox(height: 14),
            _TagWrap(tags: entry.tags),
          ],
          const SizedBox(height: 18),
          const Divider(color: AppColors.divider),
          const SizedBox(height: 12),
          Text(
            entry.body.isEmpty ? '暂无详细内容' : entry.body,
            key: const Key('world-detail-body'),
            style: const TextStyle(fontSize: 16, height: 1.65),
          ),
        ],
      ),
    );
  }
}

class _WorldImage extends StatelessWidget {
  const _WorldImage({
    required this.url,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
  });

  final String url;
  final double width;
  final double height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      key: const Key('world-image-fallback'),
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.field,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(Icons.auto_awesome_outlined, color: AppColors.textMuted),
    );
    if (url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

class _TagWrap extends StatelessWidget {
  const _TagWrap({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.field,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(tag, style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}

class _WorldMessageState extends StatelessWidget {
  const _WorldMessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
