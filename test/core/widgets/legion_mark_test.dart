import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/widgets/legion_mark.dart';

void main() {
  testWidgets('shows the Legion mark at the requested size and color', (
    tester,
  ) async {
    const color = Color(0xFF8056D6);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: LegionMark(color: color, size: 40)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(LegionMark)), const Size(40, 40));
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/branding/legion_mark.png',
    );
    expect(image.color, color);
    expect(tester.takeException(), isNull);
  });
}
