import 'dart:convert';

import 'package:civiclens/api_client.dart';
import 'package:civiclens/auth_service.dart';
import 'package:civiclens/main.dart';
import 'package:civiclens/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _photoUrl = 'http://127.0.0.1:8000/media/report_photos/light.jpg';

Map<String, dynamic> _report(
  int id,
  String citizen,
  String title,
  String issueType,
  double latitude,
  double longitude, {
  String photo = '',
}) {
  return {
    'id': id,
    'citizen': citizen,
    'title': title,
    'description': '$title description',
    'issue_type': issueType,
    'latitude': latitude.toStringAsFixed(6),
    'longitude': longitude.toStringAsFixed(6),
    'photo': photo,
    'status': 'PENDING',
    'verified_by': null,
    'created_at': '2026-11-09T07:30:04Z',
  };
}

final _light = _report(
    3, 'test2', 'light', 'STREETLIGHT', 12.999587, 74.795824,
    photo: _photoUrl);
final _pothole = _report(2, 'test1', 'potholes', 'POTHOLE', 12.999583, 74.795826);
final _distantPothole = _report(2, 'test1', 'potholes', 'POTHOLE', 13.02, 74.795826);
final _newGarbage = _report(4, 'test3', 'garbage', 'GARBAGE', 12.98, 74.795826);

void main() {
  late List<Map<String, dynamic>> serverReports;
  late int publicFetches;

  Future<void> openMap(WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'civiclens.accessToken': 'token',
      'civiclens.refreshToken': 'refresh',
    });
    final service = AuthService(
      api: ApiClient(
        client: MockClient((request) async {
          switch (request.url.path) {
            case '/api/reports/all/':
              publicFetches++;
              return http.Response(jsonEncode(serverReports), 200);
            case '/api/reports/my/':
              return http.Response(jsonEncode([_light]), 200);
            default:
              return http.Response(
                jsonEncode({
                  'id': 2,
                  'username': 'test2',
                  'email': 't@example.com',
                  'role': 'CITIZEN',
                  'points': 0,
                  'is_official_approved': false,
                }),
                200,
              );
          }
        }),
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        authService: service,
        profile: const UserProfile(
          id: 2,
          username: 'test2',
          email: 't@example.com',
          role: 'CITIZEN',
          points: 0,
          isOfficialApproved: false,
        ),
        onLoginSuccess: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Public Map'));
    await tester.pumpAndSettle();
  }

  Finder pins() => find.descendant(
        of: find.byType(FlutterMap),
        matching: find.byIcon(Icons.location_pin),
      );

  setUp(() => publicFetches = 0);

  testWidgets('separate pins for different citizens open the right report',
      (tester) async {
    serverReports = [_light, _distantPothole];
    await openMap(tester);

    expect(pins(), findsNWidgets(2));

    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('report-marker-3')),
      matching: find.byIcon(Icons.location_pin),
    ));
    await tester.pumpAndSettle();

    expect(find.text('light'), findsOneWidget);
    expect(find.text('Category: Lighting'), findsOneWidget);
    expect(find.text('Status: Pending verification'), findsOneWidget);
    expect(find.text('Submitted by: test2'), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) =>
          widget is Image &&
          widget.image is NetworkImage &&
          (widget.image as NetworkImage).url == _photoUrl),
      findsOneWidget,
    );
  });

  testWidgets('reports at nearly the same spot are all reachable',
      (tester) async {
    serverReports = [_light, _pothole];
    await openMap(tester);

    expect(pins(), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(pins());
    await tester.pumpAndSettle();

    expect(find.text('2 reports in this area'), findsOneWidget);
    expect(find.text('potholes'), findsOneWidget);

    await tester.tap(find.text('light'));
    await tester.pumpAndSettle();

    expect(find.text('Submitted by: test2'), findsOneWidget);
    expect(find.text('Category: Lighting'), findsOneWidget);
  });

  testWidgets('refresh button shows a newly submitted report', (tester) async {
    serverReports = [_light, _distantPothole];
    await openMap(tester);
    expect(pins(), findsNWidgets(2));

    serverReports = [_newGarbage, _light, _distantPothole];
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(pins(), findsNWidgets(3));
  });

  testWidgets('switching tabs fetches fresh reports', (tester) async {
    serverReports = [_light, _distantPothole];
    await openMap(tester);
    final fetchesBefore = publicFetches;

    serverReports = [_newGarbage, _light, _distantPothole];
    await tester.tap(find.text('My Reports'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Public Map'));
    await tester.pumpAndSettle();

    expect(publicFetches, fetchesBefore + 2);
    expect(pins(), findsNWidgets(3));
  });
}
