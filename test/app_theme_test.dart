import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:suki/main.dart';

void main() {
  test('navigation labels keep the app font family', () {
    final theme = buildAppTheme();
    expect(theme.textTheme.bodyMedium?.fontFamily, 'IceMoon');

    // NavigationRail 用 DefaultTextStyle 整体替换环境样式，
    // label 样式不带 fontFamily 就会掉出 IceMoon 字体。
    final rail = theme.navigationRailTheme;
    expect(rail.selectedLabelTextStyle?.fontFamily, 'IceMoon');
    expect(rail.unselectedLabelTextStyle?.fontFamily, 'IceMoon');

    // 底部 NavigationBar 同样显式声明。
    final bar = theme.navigationBarTheme.labelTextStyle;
    expect(bar?.resolve(const <WidgetState>{})?.fontFamily, 'IceMoon');
    expect(
      bar?.resolve(const <WidgetState>{WidgetState.selected})?.fontFamily,
      'IceMoon',
    );
  });
}
