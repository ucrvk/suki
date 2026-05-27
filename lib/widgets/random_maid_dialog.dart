import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 弹出一个对话框，随机展示一位女仆的头像、昵称、介绍和标签，
/// 用户可以点击「再来一个」按钮继续随机。
void showRandomMaidDialog(
  BuildContext context,
  List<Map<String, dynamic>> maids,
) {
  if (maids.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('没有可展示的女仆')));
    return;
  }

  showDialog(
    context: context,
    builder: (ctx) => _RandomMaidDialog(maids: maids),
  );
}

class _RandomMaidDialog extends StatefulWidget {
  const _RandomMaidDialog({required this.maids});

  final List<Map<String, dynamic>> maids;

  @override
  State<_RandomMaidDialog> createState() => _RandomMaidDialogState();
}

class _RandomMaidDialogState extends State<_RandomMaidDialog>
    with SingleTickerProviderStateMixin {
  late Map<String, dynamic> _currentMaid;
  int _currentIndex = -1;
  final _random = Random();
  late AnimationController _animController;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _pickRandom();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _pickRandom() {
    if (widget.maids.length == 1) {
      _currentMaid = widget.maids.first;
    } else {
      int newIndex;
      do {
        newIndex = _random.nextInt(widget.maids.length);
      } while (newIndex == _currentIndex);
      _currentIndex = newIndex;
      _currentMaid = widget.maids[newIndex];
    }
    _animController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final name = (_currentMaid['name'] ?? '未命名').toString();
    final image = (_currentMaid['image'] ?? '').toString();
    final signature = (_currentMaid['signature'] ?? '').toString();
    final tags =
        (_currentMaid['tags'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: FadeTransition(
          opacity: _fadeIn,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 头像区域 ──
                Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: image.isEmpty
                          ? const ColoredBox(
                              color: Color(0xFFECDCF2),
                              child: Center(
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  size: 48,
                                  color: Color(0xFFB8AEC1),
                                ),
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: image,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              placeholder: (context, url) => const ColoredBox(
                                color: Color(0xFFECDCF2),
                                child: Center(
                                  child: SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) =>
                                  const ColoredBox(
                                    color: Color(0xFFECDCF2),
                                    child: Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        size: 48,
                                        color: Color(0xFFB8AEC1),
                                      ),
                                    ),
                                  ),
                            ),
                    ),
                    // 关闭按钮
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Material(
                        color: Colors.black26,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // ── 信息区域 ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 昵称 + 🎲 标识
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF3A3250),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text('🎲', style: TextStyle(fontSize: 18)),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // 介绍 / 签名
                      Text(
                        signature.isEmpty ? '这位女仆还没有签名~' : signature,
                        style: const TextStyle(
                          color: Color(0xFFFF4FA5),
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 标签
                      if (tags.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: tags
                              .map(
                                (tag) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFEAF4),
                                    border: Border.all(
                                      color: const Color(0xFFFF8CC3),
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    tag,
                                    style: const TextStyle(
                                      color: Color(0xFFD31F7C),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                    ],
                  ),
                ),

                // ── 再来一个按钮 ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                  child: FilledButton.icon(
                    onPressed: () {
                      setState(() => _pickRandom());
                    },
                    icon: const Icon(Icons.casino_outlined, size: 20),
                    label: const Text(
                      '再来一个',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5DAF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
