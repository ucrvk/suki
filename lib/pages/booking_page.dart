import 'dart:async';

import 'package:flutter/material.dart';

import '../models/booking_script_entry.dart';
import '../services/booking_config_service.dart';
import '../services/booking_script_service.dart';
import '../theme/app_colors.dart';

abstract interface class BookingDataSource {
  Future<List<BookingScriptEntry>> fetchScripts();
}

class RepositoryBookingDataSource implements BookingDataSource {
  RepositoryBookingDataSource([BookingScriptService? service])
    : _service = service ?? BookingScriptService();

  final BookingScriptService _service;

  @override
  Future<List<BookingScriptEntry>> fetchScripts() => _service.fetchScripts();
}

class BookingPageController {
  VoidCallback? _scrollToTop;
  VoidCallback? _refresh;

  void scrollToTop() => _scrollToTop?.call();
  void refresh() => _refresh?.call();
}

class BookingPage extends StatefulWidget {
  const BookingPage({
    super.key,
    this.controller,
    this.dataSource,
    this.configDataSource,
  });

  final BookingPageController? controller;
  final BookingDataSource? dataSource;
  final BookingConfigDataSource? configDataSource;

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {

  final ScrollController _scrollController = ScrollController();
  late final BookingDataSource _dataSource;
  late final BookingConfigDataSource _configDataSource;
  List<BookingScriptEntry> _scripts = const [];
  Object? _error;
  bool _loading = true;
  bool _refreshing = false;
  bool _bookingEnabled = true;

  @override
  void initState() {
    super.initState();
    _dataSource = widget.dataSource ?? RepositoryBookingDataSource();
    _configDataSource =
        widget.configDataSource ?? RepositoryBookingConfigDataSource();
    widget.controller?._scrollToTop = _scrollToTop;
    widget.controller?._refresh = () => unawaited(_refresh(showFailure: true));
    unawaited(_refresh(showFailure: false));
  }

  @override
  void dispose() {
    widget.controller?._scrollToTop = null;
    widget.controller?._refresh = null;
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refresh({required bool showFailure}) async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      if (_scripts.isEmpty) _loading = true;
      _error = null;
    });
    List<BookingScriptEntry>? scripts;
    Object? scriptsError;
    try {
      scripts = await _dataSource.fetchScripts();
    } catch (error) {
      scriptsError = error;
    }
    bool? bookingEnabled;
    try {
      bookingEnabled = await _configDataSource.fetchBookingEnabled();
    } catch (_) {
      bookingEnabled = null;
    }
    if (!mounted) return;
    setState(() {
      if (bookingEnabled != null) _bookingEnabled = bookingEnabled;
      if (scripts != null) {
        _scripts = scripts;
        _loading = false;
      } else if (_scripts.isEmpty) {
        _error = scriptsError;
        _loading = false;
      } else if (showFailure) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('刷新失败，已保留当前内容')));
      }
      _refreshing = false;
    });
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '预约',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_refreshing)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
              ],
            ),
          ),
          if (!_bookingEnabled) _buildBookingDisabledBanner(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBookingDisabledBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        key: const Key('booking-disabled-banner'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.outline),
        ),
        child: const Row(
          children: [
            Icon(Icons.pause_circle_outline, size: 20, color: AppColors.accent),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '预约未开始，当前无法预约',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _scripts.isEmpty) {
      return _MessageState(
        icon: Icons.cloud_off_rounded,
        title: '预约项目加载失败',
        message: _error.toString(),
        actionLabel: '重试',
        onAction: () => _refresh(showFailure: false),
      );
    }
    if (_scripts.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _refresh(showFailure: true),
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 150),
            _MessageState(
              icon: Icons.auto_stories_outlined,
              title: '暂无可预约的项目',
              message: '下拉即可重新获取',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _refresh(showFailure: true),
      child: ListView.separated(
        key: const Key('booking-list'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _scripts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, index) => _buildScriptCard(_scripts[index]),
      ),
    );
  }

  Widget _buildScriptCard(BookingScriptEntry script) {
    return Container(
      key: ValueKey(script.id),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.outline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            script.name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          if (script.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in script.tags)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                    backgroundColor: AppColors.field,
                    label: Text(
                      tag,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ),
              ],
            ),
          ],
          if (script.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              script.description,
              style: const TextStyle(
                color: AppColors.textMuted,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('booking-apply-button'),
              onPressed: null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                disabledBackgroundColor: AppColors.fieldDisabled,
                foregroundColor: AppColors.accentInk,
                disabledForegroundColor: AppColors.textDisabled,
              ),
              child: const Text('预约（即将开放）'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
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
            Icon(icon, size: 50, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
