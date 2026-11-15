import 'package:flutter_test/flutter_test.dart';

import 'package:noor_quran/main.dart';

void main() {
  testWidgets('App starts and shows the home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const NoorQuranApp());
    await tester.pump();

    expect(find.text('لا تنسَ ذكر الله'), findsOneWidget);
    expect(find.text('أوقات الصلاة'), findsOneWidget);
  });
}
