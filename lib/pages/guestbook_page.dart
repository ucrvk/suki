import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:async';

import '../app_shell.dart';
import '../services/guestbook_cache_service.dart';
import '../services/guestbook_service.dart';
import '../services/supabase_service.dart';
import '../widgets/main_app_bar.dart';

class GuestbookPage extends StatefulWidget {
  const GuestbookPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<GuestbookPage> createState() => GuestbookPageState();
}

class GuestbookPageState extends State<GuestbookPage> {
  static const int _pageSize = 20;

  final List<GuestbookEntry> _entries = [];
  final Set<String> _likedIds = {};
  int _visibleCount = 0;
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _error;
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
    _loadEntries();
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

  Future<void> refreshData() => _loadEntries(forceRefresh: true);

  Future<void> showSubmitSheet() => _showSubmitMessageSheet();

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
    await _loadEntries(forceRefresh: true);
  }

  Future<void> _loadEntries({bool forceRefresh = false}) async {
    if (_isLoading) return;

    try {
      if (!forceRefresh) {
        final cached = await GuestbookCacheService.loadCachedSnapshot();
        if (cached != null) {
          if (!mounted) return;
          setState(() {
            _entries
              ..clear()
              ..addAll(cached.entries);
            _visibleCount = _preservedVisibleCount(cached.entries.length);
            _error = null;
            _isLoading = false;
          });
          unawaited(_refreshEntriesInBackground());
          return;
        }
      }

      setState(() {
        _isLoading = true;
        _error = null;
      });

      final snapshot = forceRefresh
          ? await GuestbookCacheService.refreshSnapshot()
          : await GuestbookCacheService.getSnapshot(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(snapshot.entries);
        _visibleCount = _preservedVisibleCount(snapshot.entries.length);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    await _loadEntries(forceRefresh: true);
  }

  int _initialVisibleCount(int total) {
    if (total <= 0) return 0;
    return total < _pageSize ? total : _pageSize;
  }

  int _preservedVisibleCount(int total) {
    if (_visibleCount <= 0) return _initialVisibleCount(total);
    if (_visibleCount > total) return total;
    return _visibleCount;
  }

  Future<void> _refreshEntriesInBackground() async {
    try {
      final snapshot = await GuestbookCacheService.refreshSnapshot();
      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(snapshot.entries);
        _visibleCount = _preservedVisibleCount(snapshot.entries.length);
      });
    } catch (_) {
      // Keep the cached guestbook if refresh fails.
    }
  }

  Future<void> _toggleLike(GuestbookEntry entry) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先登录后再点赞')));
      return;
    }

    final index = _entries.indexWhere((e) => e.id == entry.id);
    if (index == -1) return;

    // Optimistic update
    final wasLiked = _likedIds.contains(entry.id);
    setState(() {
      if (wasLiked) {
        _likedIds.remove(entry.id);
        _entries[index] = GuestbookEntry(
          id: entry.id,
          userId: entry.userId,
          username: entry.username,
          avatarUrl: entry.avatarUrl,
          content: entry.content,
          likes: (entry.likes - 1).clamp(0, 999999),
          approved: entry.approved,
          createdAt: entry.createdAt,
          updatedAt: entry.updatedAt,
          pinned: entry.pinned,
        );
      } else {
        _likedIds.add(entry.id);
        _entries[index] = GuestbookEntry(
          id: entry.id,
          userId: entry.userId,
          username: entry.username,
          avatarUrl: entry.avatarUrl,
          content: entry.content,
          likes: entry.likes + 1,
          approved: entry.approved,
          createdAt: entry.createdAt,
          updatedAt: entry.updatedAt,
          pinned: entry.pinned,
        );
      }
    });

    try {
      final result = await SupabaseService.client.rpc(
        'toggle_guestbook_like',
        params: {'p_message_id': entry.id},
      );
      // Server returns true=liked, false=unliked — sync with actual result
      final bool serverLiked = result == true;
      if (!mounted) return;
      setState(() {
        if (serverLiked) {
          _likedIds.add(entry.id);
        } else {
          _likedIds.remove(entry.id);
        }
        // Re-read actual count from next refresh; keep optimistic for now
      });
      unawaited(_refreshEntriesInBackground());
    } on PostgrestException catch (e) {
      // Revert on error
      if (!mounted) return;
      setState(() {
        if (wasLiked) {
          _likedIds.add(entry.id);
          _entries[index] = entry;
        } else {
          _likedIds.remove(entry.id);
          _entries[index] = entry;
        }
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (wasLiked) {
          _likedIds.add(entry.id);
          _entries[index] = entry;
        } else {
          _likedIds.remove(entry.id);
          _entries[index] = entry;
        }
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

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildBody();
    }
    return Scaffold(
      appBar: MainAppBar(
        title: Text('留言 (${_entries.length})'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSubmitting ? null : _showSubmitMessageSheet,
        icon: _isSubmitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.edit_note_rounded),
        label: Text(_isSubmitting ? '提交中' : '写留言'),
      ),
      body: _buildBody(),
    );
  }

  Future<void> _showSubmitMessageSheet() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后再留言')),
      );
      return;
    }

    String draftContent = '';
    final shouldSubmit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '写留言',
                style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                minLines: 3,
                maxLines: 6,
                maxLength: 300,
                onChanged: (value) => draftContent = value,
                decoration: const InputDecoration(
                  hintText: '请输入留言内容',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (draftContent.trim().isEmpty) {
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        const SnackBar(content: Text('留言内容不能为空')),
                      );
                      return;
                    }
                    Navigator.of(sheetContext).pop(true);
                  },
                  child: const Text('提交留言'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (shouldSubmit != true) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final messageId = await GuestbookService.submitGuestbookMessage(
        content: draftContent,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('留言提交成功: $messageId')));
      await _loadEntries(forceRefresh: true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      } else {
        _isSubmitting = false;
      }
    }
  }

  Widget _buildBody() {
    if (_error != null && _entries.isEmpty) {
      return _buildErrorWidget();
    }

    if (_entries.isEmpty && !_isLoading) {
      return RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 220),
            Center(
              child: Text(
                '暂无留言',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = _columnCount(constraints.maxWidth);
          final visibleEntries = _entries.take(_visibleCount).toList();
          final hasTailTile = _visibleCount < _entries.length;
          final itemCount = visibleEntries.length + (hasTailTile ? 1 : 0);

          return MasonryGridView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
            gridDelegate: SliverSimpleGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: count,
            ),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            itemCount: itemCount,
            itemBuilder: (context, index) {
              if (hasTailTile && index == itemCount - 1) {
                return _buildLoadMoreWidgetTile();
              }
              return _buildEntryCard(visibleEntries[index]);
            },
          );
        },
      ),
    );
  }

  Widget _buildEntryCard(GuestbookEntry entry) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPinned = entry.pinned;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
        color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(entry, isPinned, colorScheme),
            const SizedBox(height: 10),
            _buildContent(entry.content),
            const SizedBox(height: 10),
            _buildFooter(entry, colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    GuestbookEntry entry,
    bool isPinned,
    ColorScheme colorScheme,
  ) {
    return Row(
      children: [
        _buildAvatar(entry),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      entry.username,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isPinned) ...[
                    const SizedBox(width: 6),
                    Text(
                      '置顶',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _formatTime(entry.createdAt),
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar(GuestbookEntry entry) {
    final colorScheme = Theme.of(context).colorScheme;

    if (entry.avatarUrl != null && entry.avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: colorScheme.surfaceContainerHighest,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: entry.avatarUrl!,
            width: 36,
            height: 36,
            fit: BoxFit.cover,
            errorWidget: (context, url, error) => Icon(
              Icons.person,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 18,
      backgroundColor: colorScheme.primaryContainer,
      child: Text(
        entry.username.isNotEmpty ? entry.username.characters.first : '?',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _buildContent(String content) {
    return Text(content, style: const TextStyle(fontSize: 14, height: 1.5));
  }

  Widget _buildFooter(GuestbookEntry entry, ColorScheme colorScheme) {
    final isLiked = _likedIds.contains(entry.id);
    return GestureDetector(
      onTap: () => _toggleLike(entry),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLiked ? Icons.thumb_up_alt_rounded : Icons.thumb_up_outlined,
            size: 14,
            color: isLiked ? const Color(0xFFFF5DAF) : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            entry.likes > 0 ? '${entry.likes}' : '',
            style: TextStyle(
              fontSize: 12,
              fontWeight: isLiked ? FontWeight.w600 : FontWeight.normal,
              color: isLiked ? const Color(0xFFFF5DAF) : colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadMoreWidgetTile() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: _visibleCount >= _entries.length
              ? null
              : () {
                  setState(() {
                    _visibleCount = (_visibleCount + _pageSize).clamp(0, _entries.length);
                  });
                },
          icon: const Icon(Icons.expand_more, size: 18),
          label: const Text('加载更多'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              '加载失败',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '未知错误',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => _loadEntries(forceRefresh: true),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';

    return '${dateTime.year}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.day.toString().padLeft(2, '0')}';
  }
}

