import 'package:flutter_test/flutter_test.dart';

import 'package:noor_quran/main.dart';

void main() {
  testWidgets('App starts and shows the Quran tab', (WidgetTester tester) async {
    await tester.pumpWidget(const NoorQuranApp());

    expect(find.text('نور القرآن'), findsOneWidget);
    expect(find.text('المصحف الشريف'), findsOneWidget);
  });
}
