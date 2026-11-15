import 'package:flutter_test/flutter_test.dart';

import 'package:noor_quran/main.dart';

void main() {
  testWidgets('App starts and shows the surah list', (WidgetTester tester) async {
    await tester.pumpWidget(const NoorQuranApp());
    await tester.pumpAndSettle();

    expect(find.text('نور القرآن'), findsOneWidget);
    expect(find.text('سورة الفاتحة'), findsOneWidget);
  });
}
