import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eye_disease_detector/main.dart';

void main() {
  testWidgets('shows login screen for signed-out users',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const EyeDiseaseApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Sign in to continue'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('restores the home screen when a token exists',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'auth_token': 'demo-token',
      'username': 'demo-user',
      'role': 'patient',
    });

    await tester.pumpWidget(const EyeDiseaseApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Start Eye Scan'), findsOneWidget);
  });
}
