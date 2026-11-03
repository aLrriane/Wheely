import 'package:flutter_test/flutter_test.dart';

import 'package:wheely_access/main.dart';

void main() {
  testWidgets('Log In opens Account page and Log Out returns',
      (WidgetTester tester) async {
    await tester.pumpWidget(const WheelyAccessApp());

    // App starts on the login page.
    expect(find.text('Username'), findsOneWidget);

    // Tap the Log In button (the one that is a button, not the heading).
    await tester.tap(find.widgetWithText(ElevatedButton, 'Log In'));
    await tester.pumpAndSettle();
    expect(find.text('email@gmail.com'), findsOneWidget);

    // Log out goes back to the login page.
    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();
    expect(find.text('Username'), findsOneWidget);
  });
}
