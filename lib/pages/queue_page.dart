import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_shell.dart';
import '../services/maid_catalog_cache_service.dart';
import '../services/sysbooking_api_service.dart';
import '../services/sysbooking_session_store.dart';
import '../services/supabase_service.dart';
import '../widgets/main_app_bar.dart';

class QueuePage extends StatefulWidget {
  const QueuePage({super.key});

  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
  final ScrollController _scrollController = ScrollController();
  late final VoidCallback _tabListener;
  late final VoidCallback _tabReselectListener;

  bool _loading = false;
  bool _promptingLogin = false;
  bool _bootstrapped = false;
  String? _error;
  String? _bookingToken;
  List<SysbookingQueueItem> _items = const [];
  Map<String, String> _maidNameById = const <String, String>{};
  final Set<String> _busyBookingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabListener = _handleTabChanged;
    _tabReselectListener = _handleTabReselect;
    AppShell.tabIndexNotifier.addListener(_tabListener);
    AppShell.tabReselectNotifier.addListener(_tabReselectListener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_maybeBootstrap());
    });
  }

  @override
  void dispose() {
    AppShell.tabIndexNotifier.removeListener(_tabListener);
    AppShell.tabReselectNotifier.removeListener(_tabReselectListener);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (!mounted) return;
    if (AppShell.tabIndexNotifier.value == AppShell.queueTabIndex()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_maybeBootstrap(forceRefresh: true));
      });
    }
  }

  void _handleTabReselect() {
    if (!mounted) return;
    final event = AppShell.tabReselectNotifier.value;
    if (event == null || event.index != AppShell.queueTabIndex()) return;
    if (event.action == TabReselectAction.scrollToTop) {
      if (_scrollController.hasClients) {
        unawaited(_scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ));
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_maybeBootstrap(forceRefresh: true));
    });
  }

  Future<List<_QueueMaidChoice>> _loadQueueMaidChoices() async {
    final snapshot = await MaidCatalogCacheService.getSnapshot();
    final choices = <_QueueMaidChoice>[];

    for (final maid in snapshot.maids) {
      final vrcid = (maid['vrcid'] ?? '').toString().trim();
      if (vrcid.isEmpty || snapshot.hiddenMaidVrcids.contains(vrcid)) continue;

      final name = (maid['name'] ?? '').toString().trim();
      choices.add(
        _QueueMaidChoice(
          vrcid: vrcid,
          label: name.isEmpty ? vrcid : name,
        ),
      );
    }

    choices.sort((a, b) => a.label.compareTo(b.label));
    return choices;
  }

  String _queueItemKey(SysbookingQueueItem item) {
    final bookingId = item.bookingId.trim();
    if (bookingId.isNotEmpty) return bookingId;
    return '${item.maidId.trim()}|${item.timeslot}';
  }

  bool _isItemBusy(SysbookingQueueItem item) {
    return _busyBookingIds.contains(_queueItemKey(item));
  }

  String _displayMaidName(SysbookingQueueItem item) {
    final maidName = _maidNameById[item.maidId.trim()]?.trim() ?? '';
    if (maidName.isNotEmpty) return maidName;
    return item.maidId.trim().isEmpty ? '未命名女仆' : item.maidId.trim();
  }

  Map<String, String> _buildMaidNameMap() {
    final result = <String, String>{};
    for (final maid in _cachedMaids) {
      final vrcid = (maid['vrcid'] ?? '').toString().trim();
      if (vrcid.isEmpty) continue;
      final name = (maid['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      result[vrcid] = name;
    }
    return result;
  }

  List<Map<String, dynamic>> _cachedMaids = const <Map<String, dynamic>>[];

  void _applyCatalogSnapshot(MaidCatalogSnapshot snapshot) {
    _cachedMaids = snapshot.maids;
    _maidNameById = _buildMaidNameMap();
  }

  void _replaceItem(SysbookingQueueItem nextItem) {
    final key = _queueItemKey(nextItem);
    final index = _items.indexWhere((item) => _queueItemKey(item) == key);
    if (index == -1) return;
    final updated = List<SysbookingQueueItem>.from(_items);
    updated[index] = nextItem;
    _items = updated;
  }

  void _removeItem(SysbookingQueueItem item) {
    final key = _queueItemKey(item);
    _items = _items.where((value) => _queueItemKey(value) != key).toList();
  }

  Future<void> _refreshQueueState({bool forceRefresh = false}) async {
    if (!mounted) return;
    if (AppShell.tabIndexNotifier.value != AppShell.queueTabIndex() && !forceRefresh) {
      return;
    }
    if (_loading) return;
    if (!_bootstrapped && !forceRefresh) {
      _bootstrapped = true;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final cachedToken = await SysbookingSessionStore.loadBookingToken();
      if (cachedToken != null) {
        try {
          final items = await SysbookingApiService.fetchQueueList(cachedToken);
          MaidCatalogSnapshot? catalogSnapshot;
          try {
            catalogSnapshot = await MaidCatalogCacheService.getSnapshot(forceRefresh: forceRefresh);
          } catch (_) {
            catalogSnapshot = null;
          }
          if (!mounted) return;
          setState(() {
            _bookingToken = cachedToken;
            _items = items;
            if (catalogSnapshot != null) {
              _applyCatalogSnapshot(catalogSnapshot);
            }
            _loading = false;
          });
          return;
        } on SysbookingUnauthorizedException {
          await SysbookingSessionStore.clearBookingToken();
        }
      }

      final email = await _resolvePrefillEmail();
      final credentials = await _showLoginDialog(prefillEmail: email);
      if (credentials == null) {
        if (!mounted) return;
        setState(() {
          _bookingToken = null;
          _items = const [];
          _loading = false;
          _error = '需要登录后才能查看排队预约';
        });
        return;
      }

      final token = await SysbookingApiService.exchangeSessionForBookingToken(
        session: credentials.session,
      );
      await SysbookingSessionStore.saveBookingToken(token);
      await SysbookingSessionStore.saveLastEmail(credentials.email);
      final items = await SysbookingApiService.fetchQueueList(token);
      MaidCatalogSnapshot? catalogSnapshot;
      try {
        catalogSnapshot = await MaidCatalogCacheService.getSnapshot(forceRefresh: forceRefresh);
      } catch (_) {
        catalogSnapshot = null;
      }
      if (!mounted) return;
      setState(() {
        _bookingToken = token;
        _items = items;
        if (catalogSnapshot != null) {
          _applyCatalogSnapshot(catalogSnapshot);
        }
        _loading = false;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } on SysbookingApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
      if (e is SysbookingUnauthorizedException) {
        await SysbookingSessionStore.clearBookingToken();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _handleUnauthorizedAction(String message) async {
    await SysbookingSessionStore.clearBookingToken();
    if (!mounted) return;
    setState(() {
      _bookingToken = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    await _refreshQueueState(forceRefresh: true);
  }

  Future<void> _handleAddQueuePressed() async {
    if (_loading) return;

    if (_bookingToken == null) {
      await _maybeBootstrap(forceRefresh: false);
      if (!mounted || _bookingToken == null) return;
    }

    List<_QueueMaidChoice> choices;
    try {
      choices = await _loadQueueMaidChoices();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
      return;
    }

    if (!mounted) return;
    if (choices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可用于添加排队的女仆')),
      );
      return;
    }

    final result = await _showAddQueueDialog(choices);
    if (result == null || !mounted) return;

    if (result.kind == _AddQueueDialogResultKind.created) {
      MaidCatalogCacheService.invalidate();
      await _maybeBootstrap(forceRefresh: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已添加排队')),
      );
      return;
    }

    if (result.kind == _AddQueueDialogResultKind.unauthorized) {
      await SysbookingSessionStore.clearBookingToken();
      if (!mounted) return;
      setState(() {
        _bookingToken = null;
      });
      await _maybeBootstrap(forceRefresh: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  Future<void> _toggleAutoqueue(SysbookingQueueItem item) async {
    final bookingId = item.bookingId.trim();
    if (bookingId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('缺少 booking_id，暂时无法切换自动排队')),
      );
      return;
    }
    if (_busyBookingIds.contains(bookingId)) return;

    final previous = item.autoqueue;
    final nextValue = !previous;

    setState(() {
      _busyBookingIds.add(bookingId);
      _replaceItem(
        SysbookingQueueItem(
          bookingId: item.bookingId,
          maidId: item.maidId,
          timeslot: item.timeslot,
          queue: item.queue,
          autoqueue: nextValue,
        ),
      );
    });

    try {
      final bookingToken = _bookingToken?.trim() ?? '';
      if (bookingToken.isEmpty) {
        throw const SysbookingApiException('登录状态已失效，请重新登录');
      }

      await SysbookingApiService.updateQueueAutoqueue(
        bookingToken: bookingToken,
        bookingId: bookingId,
        autoqueue: nextValue,
      );
      if (!mounted) return;
      unawaited(_refreshQueueState(forceRefresh: true));
    } on SysbookingUnauthorizedException catch (e) {
      if (!mounted) return;
      await _handleUnauthorizedAction(e.message);
    } on SysbookingApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _replaceItem(
          SysbookingQueueItem(
            bookingId: item.bookingId,
            maidId: item.maidId,
            timeslot: item.timeslot,
            queue: item.queue,
            autoqueue: previous,
          ),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _replaceItem(
          SysbookingQueueItem(
            bookingId: item.bookingId,
            maidId: item.maidId,
            timeslot: item.timeslot,
            queue: item.queue,
            autoqueue: previous,
          ),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyBookingIds.remove(bookingId);
        });
      } else {
        _busyBookingIds.remove(bookingId);
      }
    }
  }

  Future<void> _deleteBooking(SysbookingQueueItem item) async {
    final bookingId = item.bookingId.trim();
    if (bookingId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('缺少 booking_id，暂时无法删除预约')),
      );
      return;
    }
    if (_busyBookingIds.contains(bookingId)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除预约'),
          content: Text(
            '确定删除 ${_displayMaidName(item)} 的排队预约吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busyBookingIds.add(bookingId);
    });

    try {
      final bookingToken = _bookingToken?.trim() ?? '';
      if (bookingToken.isEmpty) {
        throw const SysbookingApiException('登录状态已失效，请重新登录');
      }

      await SysbookingApiService.deleteQueueBooking(
        bookingToken: bookingToken,
        bookingId: bookingId,
      );
      if (!mounted) return;
      setState(() {
        _removeItem(item);
      });
      unawaited(_refreshQueueState(forceRefresh: true));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('预约已删除')));
    } on SysbookingUnauthorizedException catch (e) {
      if (!mounted) return;
      await _handleUnauthorizedAction(e.message);
    } on SysbookingApiException catch (e) {
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
          _busyBookingIds.remove(bookingId);
        });
      } else {
        _busyBookingIds.remove(bookingId);
      }
    }
  }

  Future<_AddQueueDialogResult?> _showAddQueueDialog(
    List<_QueueMaidChoice> choices,
  ) async {
    var selectedMaid = choices.first;
    var selectedTimeslot = 21;
    var autoqueue = false;
    var withFriend = false;
    var submitting = false;
    String? dialogError;
    var completed = false;

    return showDialog<_AddQueueDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (selectedMaid.vrcid.isEmpty) {
                setDialogState(() {
                  dialogError = '请选择女仆';
                });
                return;
              }

              setDialogState(() {
                submitting = true;
                dialogError = null;
              });

              try {
                final bookingToken = _bookingToken?.trim() ?? '';
                if (bookingToken.isEmpty) {
                  throw const SysbookingApiException('登录状态已失效，请重新登录');
                }

                await SysbookingApiService.createQueueBooking(
                  bookingToken: bookingToken,
                  maidId: selectedMaid.vrcid,
                  timeslot: selectedTimeslot,
                  autoqueue: autoqueue,
                  withFriend: withFriend,
                );
                if (!dialogContext.mounted) return;
                completed = true;
                Navigator.of(dialogContext).pop(
                  const _AddQueueDialogResult.created(),
                );
              } on SysbookingUnauthorizedException catch (e) {
                if (!dialogContext.mounted) return;
                completed = true;
                Navigator.of(dialogContext).pop(
                  _AddQueueDialogResult.unauthorized(e.message),
                );
              } on SysbookingApiException catch (e) {
                if (!dialogContext.mounted) return;
                setDialogState(() {
                  dialogError = e.message;
                  submitting = false;
                });
              } catch (e) {
                if (!dialogContext.mounted) return;
                setDialogState(() {
                  dialogError = e.toString();
                  submitting = false;
                });
              } finally {
                if (dialogContext.mounted && !completed) {
                  setDialogState(() => submitting = false);
                }
              }
            }

            return AlertDialog(
              title: const Text('添加排队'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: selectedMaid.vrcid,
                        decoration: const InputDecoration(labelText: '女仆'),
                        items: choices
                            .map(
                              (choice) => DropdownMenuItem<String>(
                                value: choice.vrcid,
                                child: Text(choice.label),
                              ),
                            )
                            .toList(),
                        onChanged: submitting
                            ? null
                            : (value) {
                                if (value == null) return;
                                final found = choices.where((e) => e.vrcid == value).toList();
                                if (found.isEmpty) return;
                                setDialogState(() {
                                  selectedMaid = found.first;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: selectedTimeslot,
                        decoration: const InputDecoration(labelText: '时段'),
                        items: const [
                          DropdownMenuItem<int>(value: 21, child: Text('21')),
                          DropdownMenuItem<int>(value: 22, child: Text('22')),
                        ],
                        onChanged: submitting
                            ? null
                            : (value) {
                                if (value == null) return;
                                setDialogState(() {
                                  selectedTimeslot = value;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: autoqueue,
                        onChanged: submitting
                            ? null
                            : (value) => setDialogState(() {
                                  autoqueue = value;
                                }),
                        title: const Text('自动排队'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: withFriend,
                        onChanged: submitting
                            ? null
                            : (value) => setDialogState(() {
                                  withFriend = value;
                                }),
                        title: const Text('带朋友一起'),
                      ),
                      if (dialogError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          dialogError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  child: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('提交'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _maybeBootstrap({bool forceRefresh = false}) async {
    await _refreshQueueState(forceRefresh: forceRefresh);
  }

  Future<String?> _resolvePrefillEmail() async {
    final currentEmail = SupabaseService.client.auth.currentUser?.email?.trim();
    if (currentEmail != null && currentEmail.isNotEmpty) return currentEmail;
    return SysbookingSessionStore.loadLastEmail();
  }

  Future<_LoginResult?> _showLoginDialog({String? prefillEmail}) async {
    if (_promptingLogin) return null;
    _promptingLogin = true;

    final emailController = TextEditingController(text: prefillEmail ?? '');
    final passwordController = TextEditingController();
    var submitting = false;
    var completed = false;

    try {
      return await showDialog<_LoginResult>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> submit() async {
                final email = emailController.text.trim();
                final password = passwordController.text;
                if (email.isEmpty || password.isEmpty) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('请输入邮箱和密码')),
                  );
                  return;
                }

                setDialogState(() => submitting = true);

                try {
                  final authResponse = await SupabaseService.client.auth.signInWithPassword(
                    email: email,
                    password: password,
                  );
                  final session = authResponse.session;
                  if (session == null) {
                    throw Exception('登录失败，未获取到会话');
                  }
                  if (!dialogContext.mounted) return;
                  completed = true;
                  Navigator.of(dialogContext).pop(_LoginResult(email: email, session: session));
                } on AuthException catch (e) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(e.message)),
                  );
                } catch (e) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                } finally {
                  if (dialogContext.mounted && !completed) {
                    setDialogState(() => submitting = false);
                  } else {
                    submitting = false;
                  }
                }
              }

              return AlertDialog(
                title: const Text('登录'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: '邮箱'),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '密码'),
                      onSubmitted: (_) => submit(),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: submitting ? null : () => Navigator.of(dialogContext).pop(),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: submitting ? null : submit,
                    child: submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('登录并导入'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      emailController.dispose();
      passwordController.dispose();
      _promptingLogin = false;
    }
  }

  String _timeslotLabel(int timeslot) {
    switch (timeslot) {
      case 21:
        return '21';
      case 22:
        return '22';
      default:
        return timeslot.toString();
    }
  }

  String _queueLabel(int queue) {
    if (queue <= 0) return '前面无人';
    return '前面 $queue 人';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MainAppBar(
        title: const Text('排队'),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => unawaited(_maybeBootstrap(forceRefresh: true)),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _maybeBootstrap(forceRefresh: true),
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _handleAddQueuePressed,
                  icon: const Icon(Icons.playlist_add_rounded),
                  label: const Text('添加排队'),
                ),
              ),
            ),
            _buildHeaderCard(),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _buildErrorState()
            else if (_items.isEmpty)
              _buildEmptyState()
            else
              ..._items.map(_buildQueueCard),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF3A3250);
    final subColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7A7188);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        leading: const Icon(Icons.queue_play_next_rounded),
        title: Text(
          '我的排队预约',
          style: TextStyle(fontWeight: FontWeight.w800, color: titleColor),
        ),
        subtitle: Text(
          _bookingToken == null ? '需要登录后才能查看' : '已加载当前登录用户的 waiting 预约',
          style: TextStyle(color: subColor),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF3A3250);
    final subColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7A7188);

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 42, color: subColor),
          const SizedBox(height: 12),
          Text(
            '暂无正在排队的预约',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: titleColor),
          ),
          const SizedBox(height: 6),
          Text(
            '如果你有 waiting 状态的预约，这里会列出来。',
            textAlign: TextAlign.center,
            style: TextStyle(color: subColor),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF3A3250);
    final subColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7A7188);

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded, size: 42, color: subColor),
          const SizedBox(height: 12),
          Text(
            '加载失败',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: titleColor),
          ),
          const SizedBox(height: 6),
          Text(
            _error ?? '未知错误',
            textAlign: TextAlign.center,
            style: TextStyle(color: subColor),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => unawaited(_maybeBootstrap(forceRefresh: true)),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueCard(SysbookingQueueItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF3A3250);
    final subColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7A7188);
    final accent = Theme.of(context).colorScheme.primary;
    final maidName = _displayMaidName(item);
    final isBusy = _isItemBusy(item);
    final canMutate = item.bookingId.trim().isNotEmpty && !isBusy;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: accent.withValues(alpha: 0.12),
            child: Icon(Icons.badge_outlined, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  maidName,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: titleColor),
                ),
                const SizedBox(height: 8),
                Text('时段 ${_timeslotLabel(item.timeslot)}', style: TextStyle(color: subColor)),
                const SizedBox(height: 4),
                Text(_queueLabel(item.queue), style: TextStyle(color: subColor)),
                const SizedBox(height: 4),
                Text(
                  item.autoqueue ? '自动排队：开启' : '自动排队：关闭',
                  style: TextStyle(color: subColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                    onPressed: canMutate ? () => _toggleAutoqueue(item) : null,
                    icon: isBusy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(item.autoqueue ? Icons.toggle_on_rounded : Icons.toggle_off_outlined),
                    label: Text(item.autoqueue ? '关闭自动' : '开启自动'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: canMutate ? () => _deleteBooking(item) : null,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('删除预约'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueMaidChoice {
  const _QueueMaidChoice({
    required this.vrcid,
    required this.label,
  });

  final String vrcid;
  final String label;
}

class _AddQueueDialogResult {
  const _AddQueueDialogResult._(this.kind, this.message);

  const _AddQueueDialogResult.created() : this._(_AddQueueDialogResultKind.created, '');

  const _AddQueueDialogResult.unauthorized(String message)
      : this._(_AddQueueDialogResultKind.unauthorized, message);

  final _AddQueueDialogResultKind kind;
  final String message;
}

enum _AddQueueDialogResultKind {
  created,
  unauthorized,
}

class _LoginResult {
  const _LoginResult({
    required this.email,
    required this.session,
  });

  final String email;
  final Session session;
}
