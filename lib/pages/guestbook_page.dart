import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/guestbook_service.dart';
import '../services/supabase_service.dart';
import '../widgets/main_app_bar.dart';

class GuestbookPage extends StatefulWidget {
  const GuestbookPage({super.key});

  @override
  State<GuestbookPage> createState() => _GuestbookPageState();
}

class _GuestbookPageState extends State<GuestbookPage> {
  static const int _pageSize = 20;

  final List<GuestbookEntry> _entries = [];
  final Set<String> _likedIds = {};
  bool _isLoading = false;
  bool _isSubmitting = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEntries(isRefresh: true);
  }

  Future<void> _loadEntries({bool isRefresh = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final offset = isRefresh ? 0 : _entries.length;

      final response = await SupabaseService.client
          .from('suki_guestbook')
          .select()
          .eq('approved', true)
          .order('pinned', ascending: false)
          .order('created_at', ascending: false)
          .range(offset, offset + _pageSize - 1);

      final List<dynamic> data = response as List<dynamic>;
      final newEntries = data
          .map((json) => GuestbookEntry.fromJson(json))
          .toList();

      setState(() {
        if (isRefresh) {
          _entries.clear();
        }
        _entries.addAll(newEntries);
        _hasMore = newEntries.length >= _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    await _loadEntries(isRefresh: true);
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
      await _loadEntries(isRefresh: true);
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

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = _columnCount(constraints.maxWidth);
          final totalItems = _entries.length;
          final hasLoadMore = _hasMore || _isLoading;
          final rowCount = (totalItems / count).ceil() + (hasLoadMore ? 1 : 0);

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
            itemCount: rowCount,
            itemBuilder: (context, rowIndex) {
              // Last row is the load-more widget
              if (hasLoadMore && rowIndex == rowCount - 1) {
                return _buildLoadMoreWidget();
              }

              final start = rowIndex * count;
              final end =
                  (start + count) > totalItems ? totalItems : (start + count);
              final rowItems = _entries.sublist(start, end);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < count; i++) ...[
                      Expanded(
                        child: i < rowItems.length
                            ? _buildEntryCard(rowItems[i])
                            : const SizedBox.shrink(),
                      ),
                      if (i != count - 1) const SizedBox(width: 10),
                    ],
                  ],
                ),
              );
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

  Widget _buildLoadMoreWidget() {
    if (_isLoading && _entries.isNotEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasMore && _entries.isEmpty) {
      return const SizedBox.shrink();
    }

    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            '— 已经到底了 —',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: () => _loadEntries(),
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
              onPressed: () => _loadEntries(isRefresh: true),
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
