import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:suki/widgets/remote_image.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('shows the placeholder without requesting an empty url', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const RemoteImage(
          imageUrl: '',
          width: 100,
          height: 60,
          placeholder: Text('占位'),
        ),
      ),
    );

    expect(find.text('占位'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });

  testWidgets('loads network images through the caching widget', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const RemoteImage(
          imageUrl: 'https://example.com/a.png',
          width: 100,
          height: 60,
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.imageUrl, 'https://example.com/a.png');
    expect(image.width, 100);
    expect(image.height, 60);
    expect(image.fit, BoxFit.cover);
  });

  testWidgets('trims the url and clips rounded corners', (tester) async {
    await tester.pumpWidget(
      _host(
        const RemoteImage(
          imageUrl: '  https://example.com/a.png  ',
          width: 100,
          height: 60,
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .imageUrl,
      'https://example.com/a.png',
    );
    expect(find.byType(ClipRRect), findsOneWidget);
  });
}
