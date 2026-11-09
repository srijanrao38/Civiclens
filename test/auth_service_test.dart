import 'dart:convert';
import 'dart:io';

import 'package:civiclens/api_client.dart';
import 'package:civiclens/auth_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A, 0x46, 0x49, 0x46, 0, 1];
const _photoUrl = 'http://127.0.0.1:8000/media/report_photos/a.jpg';

void main() {
  late List<http.Request> requests;
  late AuthService service;

  setUp(() {
    requests = [];
    FlutterSecureStorage.setMockInitialValues({
      'civiclens.accessToken': 'token',
      'civiclens.refreshToken': 'refresh',
    });
    service = AuthService(
      api: ApiClient(
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/upload-photo/')) {
            return http.Response(jsonEncode({'photo': _photoUrl}), 201);
          }
          return http.Response(jsonEncode({'id': 1, ...jsonDecode(request.body)}), 201);
        }),
      ),
    );
  });

  Future<void> submit(double latitude, double longitude, {File? photo}) {
    return service.createReport(
      title: 'Blocked drain',
      description: 'Water is pooling.',
      issueType: 'DRAINAGE',
      latitude: latitude,
      longitude: longitude,
      photo: photo,
    );
  }

  http.Request reportRequest() =>
      requests.singleWhere((request) => request.url.path == '/api/reports/');

  final cases = <String, (double, double, double, double)>{
    'typical GPS fix': (12.973123456789, 74.857456789012, 12.973123, 74.857457),
    'negative values': (-33.86881234567, -151.20929987654, -33.868812, -151.2093),
    'carry across digits': (12.9999999, 74.0000004, 13.0, 74.0),
    'already 6 places': (12.973123, 74.857456, 12.973123, 74.857456),
    'very small values': (0.00000012, -0.0000009, 0.0, -0.000001),
  };

  cases.forEach((label, data) {
    final (latitude, longitude, expectedLatitude, expectedLongitude) = data;
    test('sends at most 6 decimal places: $label', () async {
      await submit(latitude, longitude);

      final raw = reportRequest().body;
      final body = jsonDecode(raw) as Map<String, dynamic>;
      expect(body['latitude'], expectedLatitude);
      expect(body['longitude'], expectedLongitude);
      for (final key in ['latitude', 'longitude']) {
        final sent = RegExp('"$key":([^,}]+)').firstMatch(raw)!.group(1)!;
        expect(sent, matches(RegExp(r'^-?\d+(\.\d{1,6})?$')));
      }
    });
  });

  test('photo upload precedes a report carrying every field', () async {
    final directory = Directory.systemTemp.createTempSync('civiclens');
    addTearDown(() => directory.deleteSync(recursive: true));
    final photo = File('${directory.path}/a.jpg')..writeAsBytesSync(_jpeg);

    await submit(12.973123456789, 74.857456789012, photo: photo);

    expect(requests.map((request) => request.url.path), [
      '/api/reports/upload-photo/',
      '/api/reports/',
    ]);
    expect(jsonDecode(reportRequest().body), {
      'title': 'Blocked drain',
      'description': 'Water is pooling.',
      'issue_type': 'DRAINAGE',
      'latitude': 12.973123,
      'longitude': 74.857457,
      'photo': _photoUrl,
    });
  });
}
