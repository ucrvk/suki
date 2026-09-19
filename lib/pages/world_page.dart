import 'dart:async';

import 'package:flutter/material.dart';

import '../models/world_content_entry.dart';
import '../services/world_content_service.dart';

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
  const WorldPage({super.key, this.controller, this.dataSource});

  final WorldPageController? controller;
  final WorldDataSource? dataSource;

  @override
  State<WorldPage> createState() => _WorldPageState();
}

class _WorldPageState extends State<WorldPage>
    with SingleTickerProviderStateMixin {
  static const _cardColor = Color(0xFF33205C);
  static const _accentColor = Color(0xFF9B78D1);
  static const _mutedColor = Color(0xFFC4B4DC);

  late final TabController _tabController;
  late final WorldDataSource _dataSource;
  final _scrollControllers = {
    for (final section in WorldSection.values) section: ScrollController(),
  };

  WorldContentSnapshot? _codexSnapshot;
  WorldContentSnapshot? _endingsSnapshot;
  Object? _codexError;
  Object? _endingsError;
  bool _codexLoading = true;
  bool _endingsLoading = true;
  bool _codexRefreshing = false;
  bool _endingsRefreshing = false;
  WorldSection _section = WorldSection.witch;

  @override
  void initState() {
    super.initState();
    _dataSource = widget.dataSource ?? RepositoryWorldDataSource();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(_handleTabChanged);
    widget.controller?._scrollToTop = _scrollToTop;
    widget.controller?._refresh = () => unawaited(_refreshCurrent());
    unawaited(_loadCodex());
    unawaited(_loadEndings());
  }

  @override
  void dispose() {
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
            indicatorColor: _accentColor,
            labelColor: Colors.white,
            unselectedLabelColor: _mutedColor,
            dividerColor: const Color(0xFF4A2F80),
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
    final groups = groupEndingsByScript(
      _endingsSnapshot?.entries ?? const <WorldContentEntry>[],
    );
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

    final children = <Widget>[];
    for (final group in groups.entries) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text(
            group.key,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ),
      );
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

  Widget _buildSummaryCard(WorldContentEntry entry) {
    return InkWell(
      key: ValueKey(entry.id),
      borderRadius: BorderRadius.circular(22),
      onTap: () => _showDetails(entry),
      child: Container(
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF4A2F80)),
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
                      style: const TextStyle(color: _mutedColor, height: 1.35),
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
              child: Icon(Icons.chevron_right_rounded, color: _mutedColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEndingCard(WorldContentEntry entry) {
    return InkWell(
      key: ValueKey(entry.id),
      borderRadius: BorderRadius.circular(20),
      onTap: () => _showDetails(entry),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF4A2F80)),
        ),
        child: Row(
          children: [
            const Icon(Icons.visibility_outlined, color: _accentColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (entry.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      entry.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _mutedColor),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _mutedColor),
          ],
        ),
      ),
    );
  }

  Future<void> _showDetails(WorldContentEntry entry) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF271847),
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
                style: const TextStyle(color: _WorldPageState._mutedColor),
              ),
            ],
            const SizedBox(height: 18),
          ],
          if (entry.kind == WorldContentKind.ending)
            Text(
              entry.script,
              style: const TextStyle(color: _WorldPageState._accentColor),
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
                color: _WorldPageState._mutedColor,
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
          const Divider(color: Color(0xFF4A2F80)),
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
        color: const Color(0xFF4A2F80),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(Icons.auto_awesome_outlined, color: Color(0xFFC4B4DC)),
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
              color: const Color(0xFF4A2F80),
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
            Icon(icon, size: 48, color: _WorldPageState._mutedColor),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _WorldPageState._mutedColor),
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
