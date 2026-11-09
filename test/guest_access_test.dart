import 'dart:convert';

import 'package:civiclens/api_client.dart';
import 'package:civiclens/auth_service.dart';
import 'package:civiclens/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _photoUrl = 'http://127.0.0.1:8000/media/report_photos/a.jpg';

/// The shape PublicReportSerializer returns: no citizen or verified_by.
const _guestReport = {
  'id': 7,
  'title': 'Fixed pothole',
  'description': 'Deep pothole near the crossing.',
  'issue_type': 'POTHOLE',
  'latitude': '12.973',
  'longitude': '74.857',
  'photo': _photoUrl,
  'status': 'VERIFIED',
  'created_at': '2026-11-09T07:30:04Z',
};

final _nearbyGuestReport = <String, dynamic>{
  ..._guestReport,
  'id': 8,
  'title': 'Blocked drain',
};

void main() {
  late List<http.Request> requests;
  late List<Map<String, dynamic>> guestReports;
  late String role;

  setUp(() {
    requests = [];
    guestReports = [_guestReport];
    role = 'CITIZEN';
    FlutterSecureStorage.setMockInitialValues({});
  });

  AuthService service() => AuthService(
        api: ApiClient(
          client: MockClient((request) async {
            requests.add(request);
            switch (request.url.path) {
              case '/api/auth/login/':
                return http.Response(
                    jsonEncode({'access': 'access', 'refresh': 'refresh'}), 200);
              case '/api/auth/me/':
                return http.Response(
                  jsonEncode({
                    'id': 1,
                    'username': 'someone',
                    'email': 's@example.com',
                    'role': role,
                    'points': 0,
                    'is_official_approved': role == 'OFFICIAL',
                  }),
                  200,
                );
              case '/api/reports/all/':
                return http.Response(jsonEncode(guestReports), 200);
              default:
                return http.Response('[]', 200);
            }
          }),
        ),
      );

  Future<void> openGuestMap(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(CivicLensApp(authService: service()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse the map without logging in'));
    await tester.pumpAndSettle();
  }

  Finder pins() => find.descendant(
        of: find.byType(FlutterMap),
        matching: find.byIcon(Icons.location_pin),
      );

  Future<void> submitLogin(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).at(0), 'someone');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
  }

  test('guest fetch sends no token even when a stale one is stored', () async {
    FlutterSecureStorage.setMockInitialValues({
      'civiclens.accessToken': 'expired',
      'civiclens.refreshToken': 'expired',
    });

    await service().getGuestReports();

    expect(requests.single.headers.containsKey('Authorization'), isFalse);
  });

  testWidgets('guest can open the map and see verified report details',
      (tester) async {
    await openGuestMap(tester);

    expect(pins(), findsOneWidget);

    await tester.tap(pins());
    await tester.pumpAndSettle();

    expect(find.text('Fixed pothole'), findsOneWidget);
    expect(find.text('Deep pothole near the crossing.'), findsOneWidget);
    expect(find.text('Category: Roads'), findsOneWidget);
    expect(find.text('Status: Verified'), findsOneWidget);
    expect(find.text('Approximate location: 12.973, 74.857'), findsOneWidget);
    expect(find.textContaining('Submitted by'), findsNothing);
    expect(
      find.byWidgetPredicate((widget) =>
          widget is Image &&
          widget.image is NetworkImage &&
          (widget.image as NetworkImage).url == _photoUrl),
      findsOneWidget,
    );
    expect(find.text('Verify'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });

  testWidgets('guest map still groups overlapping reports', (tester) async {
    guestReports = [_guestReport, _nearbyGuestReport];
    await openGuestMap(tester);

    expect(pins(), findsOneWidget);
    await tester.tap(pins());
    await tester.pumpAndSettle();

    expect(find.text('2 reports in this area'), findsOneWidget);
    expect(find.text('Roads • Verified'), findsNWidgets(2));
  });

  for (final (label, message) in [
    ('Report issue', 'submit a report'),
    ('My Reports', 'see your reports'),
    ('Rewards', 'earn reward points'),
  ]) {
    testWidgets('$label asks a guest to log in, without any API write',
        (tester) async {
      await openGuestMap(tester);
      requests.clear();

      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      expect(find.textContaining(message), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      expect(requests, isEmpty);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(pins(), findsOneWidget);
    });
  }

  testWidgets('prompt can send a guest to registration', (tester) async {
    await openGuestMap(tester);

    await tester.tap(find.text('Report issue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();

    expect(find.text('Create citizen account'), findsOneWidget);
    await tester.tap(find.text('Back to login'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to make your community better.'), findsOneWidget);
  });

  testWidgets('citizen logging in from the guest map reaches their home',
      (tester) async {
    await openGuestMap(tester);

    await tester.tap(find.text('Report issue'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
    await submitLogin(tester);

    expect(find.text('Community issues'), findsOneWidget);
    expect(find.text('Log in'), findsNothing);
    expect(Navigator.of(tester.element(find.text('Community issues'))).canPop(),
        isFalse);
  });

  testWidgets('official logging in from the guest map reaches the dashboard',
      (tester) async {
    role = 'OFFICIAL';
    await openGuestMap(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Log in'));
    await tester.pumpAndSettle();
    await submitLogin(tester);

    expect(find.text('Official dashboard'), findsOneWidget);
  });
}
