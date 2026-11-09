import 'dart:convert';
import 'dart:io';

import 'package:civiclens/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A, 0x46, 0x49, 0x46, 0, 1];
const _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D];
const _webp = [
  0x52, 0x49, 0x46, 0x46, 0x24, 0, 0, 0, //
  0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38, 0x20,
];

void main() {
  late Directory directory;

  setUp(() => directory = Directory.systemTemp.createTempSync('civiclens'));
  tearDown(() => directory.deleteSync(recursive: true));

  Future<String> uploadedPart(String fileName, List<int> bytes) async {
    final file = File('${directory.path}/$fileName')..writeAsBytesSync(bytes);
    late String body;
    final api = ApiClient(
      client: MockClient((request) async {
        body = latin1.decode(request.bodyBytes);
        return http.Response('{}', 201);
      }),
    );

    await api.postMultipart('/upload/', 'photo', file.path, token: 'token');
    return body;
  }

  final cases = <String, (String, List<int>, String, String)>{
    'camera jpg': ('scaled_abc.jpg', _jpeg, 'image/jpeg', 'report_photo.jpg'),
    'jpeg extension': ('a.jpeg', _jpeg, 'image/jpeg', 'report_photo.jpg'),
    'png': ('a.png', _png, 'image/png', 'report_photo.png'),
    'webp': ('a.webp', _webp, 'image/webp', 'report_photo.webp'),
    'gallery file without extension': (
      'image_picker_1',
      _jpeg,
      'image/jpeg',
      'report_photo.jpg',
    ),
    'name disagrees with bytes': (
      'scaled_1.heic',
      _jpeg,
      'image/jpeg',
      'report_photo.jpg',
    ),
  };

  cases.forEach((label, data) {
    final (fileName, bytes, mimeType, sentName) = data;
    test('sends $label with its real image type', () async {
      final body = await uploadedPart(fileName, bytes);

      expect(body, contains('name="photo"'));
      expect(body, contains('filename="$sentName"'));
      expect(body, contains('content-type: $mimeType'));
    });
  });

  test('backend rejection detail is shown to the user', () {
    final api = ApiClient(client: MockClient((_) async => http.Response('', 200)));
    final response = http.Response(
      '{"detail": "Only JPG, PNG, and WebP images are supported."}',
      400,
    );

    expect(
      () => api.ensureSuccess(response, fallback: 'Photo upload failed.'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'Only JPG, PNG, and WebP images are supported.',
        ),
      ),
    );
  });

  test('HTML error pages fall back to a readable message', () {
    final api = ApiClient(client: MockClient((_) async => http.Response('', 200)));

    expect(api.readableError('<!doctype html><h1>Bad</h1>', 'Failed.'), 'Failed.');
  });
}
