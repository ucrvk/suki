import 'package:flutter/material.dart';

/// 应用统一色板。
///
/// 深色幽紫底 + 霓虹紫罗兰强调色：保留神秘感的同时拉开层次与文字对比度。
/// 页面内不要再硬编码色值，统一引用此处常量。
class AppColors {
  const AppColors._();

  /// 页面底色，近黑的墨紫。
  static const background = Color(0xFF0B0718);

  /// 卡片/列表项表面。
  static const surface = Color(0xFF2A1A4E);

  /// 更凸起的表面（底部弹层等）。
  static const surfaceElevated = Color(0xFF33205C);

  /// 描边，用于卡片/输入框外框。
  static const outline = Color(0xFF6A45AE);

  /// 分割线，比描边弱一档。
  static const divider = Color(0xFF5B3796);

  /// 霓虹紫罗兰，强调色：图标、高亮数字、选中态、主按钮填充。
  static const accent = Color(0xFFC77DFF);

  /// 弱一档的强调色，用于插画/占位图标。
  static const accentSoft = Color(0xFFE0A8FF);

  /// 强调色填充之上的文字颜色。
  static const accentInk = Color(0xFF170A28);

  /// 填充色：标签、头像底、按钮底等小块面。
  static const field = Color(0xFF5B2F9E);

  /// 禁用态填充色。
  static const fieldDisabled = Color(0xFF3E2668);

  /// 主文字。
  static const textPrimary = Color(0xFFF6F2FF);

  /// 次要文字。
  static const textMuted = Color(0xFFCFC2E8);

  /// 禁用态文字。
  static const textDisabled = Color(0xFFA794C9);
}
