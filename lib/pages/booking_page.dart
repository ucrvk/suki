import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_shell.dart';
import '../services/booking_service.dart';
import '../services/maid_catalog_cache_service.dart';
import '../services/supabase_service.dart';
import '../widgets/maid_card.dart';
import '../widgets/random_maid_dialog.dart';
import '../widgets/main_app_bar.dart';

class MaidViewData {
  const MaidViewData({
    required this.maid,
    required this.uniqueId,
    required this.status,
    required this.isFavorite,
    required this.originalIndex,
  });

  final Map<String, dynamic> maid;
  final String uniqueId;
  final MaidStatus status;
  final bool isFavorite;
  final int originalIndex;
}

class BookingPage extends StatefulWidget {
  const BookingPage({super.key, this.forceAllBookableForTest = false});

  final bool forceAllBookableForTest;

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  static const _favoriteStorageKey = 'favorite_maid_ids';
  static const _fullThreshold = 2;

  bool _loading = true;
  String? _error;
  bool _bookingEnabled = true;
  List<Map<String, dynamic>> _maids = const [];
  List<Map<String, dynamic>> _reservations = const [];
  Set<String> _hiddenMaidVrcids = const <String>{};
  Set<String> _favoriteIds = <String>{};
  final Set<String> _submittingKeys = <String>{};
  final TextEditingController _searchController = TextEditingController();
  User? _currentUser;
  StreamSubscription<AuthState>? _authStateSub;

  @override
  void initState() {
    super.initState();
    _currentUser = SupabaseService.client.auth.currentUser;
    _authStateSub = SupabaseService.client.auth.onAuthStateChange.listen((
      event,
    ) {
      if (!mounted) return;
      setState(() {
        _currentUser = event.session?.user;
      });
    });
    _initPage();
  }

  @override
  void dispose() {
    _authStateSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initPage() async {
    await _loadFavorites();
    await _fetchMaids();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_favoriteStorageKey) ?? const <String>[];
    if (!mounted) return;
    setState(() {
      _favoriteIds = ids.toSet();
    });
  }

  Future<void> _persistFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoriteStorageKey, _favoriteIds.toList());
  }

  Future<void> _toggleFavorite(String id) async {
    setState(() {
      if (_favoriteIds.contains(id)) {
        _favoriteIds.remove(id);
      } else {
        _favoriteIds.add(id);
      }
    });
    await _persistFavorites();
  }

  Future<void> _fetchMaids({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final snapshot = await MaidCatalogCacheService.getSnapshot(
        forceRefresh: forceRefresh,
      );

      setState(() {
        _maids = snapshot.maids;
        _reservations = snapshot.reservations;
        _bookingEnabled = snapshot.bookingEnabled;
        _hiddenMaidVrcids = snapshot.hiddenMaidVrcids;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _maidUniqueId(Map<String, dynamic> maid) {
    final id = (maid['id'] ?? '').toString().trim();
    if (id.isNotEmpty) return id;
    final vrcid = (maid['vrcid'] ?? '').toString().trim();
    if (vrcid.isNotEmpty) return vrcid;
    return (maid['name'] ?? '').toString().trim();
  }

  int _reservationCountForMaid(Map<String, dynamic> maid) {
    final vrcid = (maid['vrcid'] ?? '').toString().trim();
    final name = (maid['name'] ?? '').toString().trim();
    int count = 0;
    for (final reservation in _reservations) {
      final resVrcid = (reservation['maidVrcid'] ?? '').toString().trim();
      final resName = (reservation['maidName'] ?? '').toString().trim();
      final matchByVrcid = vrcid.isNotEmpty && resVrcid == vrcid;
      final matchByName = vrcid.isEmpty && name.isNotEmpty && resName == name;
      if (matchByVrcid || matchByName) count++;
    }
    return count;
  }

  MaidStatus _statusForMaid(Map<String, dynamic> maid) {
    if (widget.forceAllBookableForTest) return MaidStatus.available;
    final disabled = maid['disabled'] == true;
    if (!_bookingEnabled || disabled) return MaidStatus.closed;
    if (_reservationCountForMaid(maid) >= _fullThreshold) {
      return MaidStatus.full;
    }
    return MaidStatus.available;
  }

  int _statusPriority(MaidStatus status) {
    switch (status) {
      case MaidStatus.available:
        return 0;
      case MaidStatus.full:
        return 1;
      case MaidStatus.closed:
        return 2;
    }
  }

  List<MaidViewData> _buildSortedMaids() {
    final items = <MaidViewData>[];
    for (int i = 0; i < _maids.length; i++) {
      final maid = _maids[i];
      if (_shouldHideMaid(maid)) continue;
      final uniqueId = _maidUniqueId(maid);
      items.add(
        MaidViewData(
          maid: maid,
          uniqueId: uniqueId,
          status: _statusForMaid(maid),
          isFavorite: _favoriteIds.contains(uniqueId),
          originalIndex: i,
        ),
      );
    }
    items.sort((a, b) {
      if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
      final statusCompare = _statusPriority(
        a.status,
      ).compareTo(_statusPriority(b.status));
      if (statusCompare != 0) return statusCompare;
      return a.originalIndex.compareTo(b.originalIndex);
    });
    return items;
  }

  bool _shouldHideMaid(Map<String, dynamic> maid) {
    final vrcid = (maid['vrcid'] ?? '').toString().trim();
    if (vrcid.isNotEmpty && _hiddenMaidVrcids.contains(vrcid)) return true;

    final name = (maid['name'] ?? '').toString().trim();
    if (name == '鱼七') return true;

    final tags =
        (maid['tags'] as List?)?.map((e) => e.toString()).toList() ??
        const <String>[];
    return tags.any((tag) => tag.contains('前台'));
  }

  List<MaidViewData> _filterMaidsBySearch(List<MaidViewData> items) {
    final keyword = _searchController.text.trim().toLowerCase();
    if (keyword.isEmpty) return items;
    return items.where((item) {
      final maid = item.maid;
      final name = (maid['name'] ?? '').toString().toLowerCase();
      final vrcid = (maid['vrcid'] ?? '').toString().toLowerCase();
      final signature = (maid['signature'] ?? '').toString().toLowerCase();
      final tags =
          (maid['tags'] as List?)?.map((e) => e.toString().toLowerCase()) ??
          const [];
      return name.contains(keyword) ||
          vrcid.contains(keyword) ||
          signature.contains(keyword) ||
          tags.any((tag) => tag.contains(keyword));
    }).toList();
  }

  bool _isSubmittingAnySlot(String uniqueId) {
    return _submittingKeys.any((key) => key.startsWith('$uniqueId|'));
  }

  Future<void> _onBookTap({required MaidViewData item}) async {
    if (item.status != MaidStatus.available) return;

    if (_currentUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先登录后再预约'),
          action: SnackBarAction(
            label: '去登录',
            onPressed: () => AppShell.switchToTab(1),
          ),
        ),
      );
      return;
    }

    String selectedSlot = BookingService.slotA;
    bool withFriend = false;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '确认预约',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('女仆：${(item.maid['name'] ?? '未命名').toString()}'),
                    const SizedBox(height: 10),
                    const Text(
                      '选择时段',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(BookingService.slotA),
                          selected: selectedSlot == BookingService.slotA,
                          onSelected: (_) {
                            setSheetState(
                              () => selectedSlot = BookingService.slotA,
                            );
                          },
                        ),
                        ChoiceChip(
                          label: Text(BookingService.slotB),
                          selected: selectedSlot == BookingService.slotB,
                          onSelected: (_) {
                            setSheetState(
                              () => selectedSlot = BookingService.slotB,
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: withFriend,
                      onChanged: (value) =>
                          setSheetState(() => withFriend = value),
                      title: const Text('是否带朋友'),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        child: const Text('确认预约'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    final slot = selectedSlot;
    final submitKey = '${item.uniqueId}|$slot';
    setState(() {
      _submittingKeys.add(submitKey);
    });

    try {
      await BookingService.addReservation(
        maid: item.maid,
        timeSlot: slot,
        withFriend: withFriend,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('预约成功')));
      MaidCatalogCacheService.invalidate();
      await _fetchMaids(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message.isEmpty ? '预约失败' : message)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submittingKeys.remove(submitKey);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleMaids = _buildSortedMaids();
    final totalCount = visibleMaids.length;
    final availableCount = visibleMaids
        .where((item) => item.status == MaidStatus.available)
        .length;

    return Scaffold(
      appBar: MainAppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '预约',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 6),
            Text(
              '($availableCount/$totalCount)',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF3A3250),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _loading || _error != null
          ? null
          : FloatingActionButton(
              onPressed: () {
                final visibleMaids = _buildSortedMaids()
                    .where((item) => !_shouldHideMaid(item.maid))
                    .map((item) => item.maid)
                    .toList();
                showRandomMaidDialog(context, visibleMaids);
              },
              tooltip: '随机女仆',
              child: const Icon(Icons.casino_outlined),
            ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('请求失败: $_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _fetchMaids, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final sortedMaids = _buildSortedMaids();
    final visibleMaids = _filterMaidsBySearch(sortedMaids);
    return RefreshIndicator(
      onRefresh: () => _fetchMaids(forceRefresh: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          int count = 1;
          if (width >= 1400) {
            count = 5;
          } else if (width >= 1100) {
            count = 4;
          } else if (width >= 760) {
            count = 3;
          } else if (width >= 520) {
            count = 2;
          }

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: '搜索女仆（昵称/VRCID/标签）',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.clear),
                                ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (!_bookingEnabled)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEAF4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFFA0CC)),
                          ),
                          child: const Text(
                            '预约系统未开放，目前全部不可预约',
                            style: TextStyle(
                              color: Color(0xFFD31F7C),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: count,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.92,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final item = visibleMaids[index];
                    return MaidCard(
                      maid: item.maid,
                      status: item.status,
                      isFavorite: item.isFavorite,
                      onToggleFavorite: () => _toggleFavorite(item.uniqueId),
                      onBook: () => _onBookTap(item: item),
                      submitting: _isSubmittingAnySlot(item.uniqueId),
                    );
                  }, childCount: visibleMaids.length),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
