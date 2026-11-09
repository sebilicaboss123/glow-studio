import 'package:flutter_test/flutter_test.dart';

import 'package:glow_studio/main.dart';

void main() {
  testWidgets('home screen shows entry actions', (WidgetTester tester) async {
    await tester.pumpWidget(const GlowStudioApp());

    expect(find.text('Glow Studio'), findsOneWidget);
    expect(find.text('Choose a photo'), findsOneWidget);
    expect(find.text('Take a photo'), findsOneWidget);
  });
}
