import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

const String apiBaseUrl = 'http://127.0.0.1:8000';

const Map<String, String> _imageExtensions = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

class ApiException implements Exception {
  final int? statusCode;
  final String message;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiClient {
  static const _requestTimeout = Duration(seconds: 15);
  final http.Client _client;

  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  Future<http.Response> get(String path, {String? token}) {
    return _client
        .get(Uri.parse('$apiBaseUrl$path'), headers: _headers(token))
        .timeout(_requestTimeout);
  }

  Future<http.Response> postJson(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _client
        .post(
          Uri.parse('$apiBaseUrl$path'),
          headers: {..._headers(token), 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout);
  }

  Future<http.Response> postMultipart(
    String path,
    String fieldName,
    String filePath, {
    String? token,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$apiBaseUrl$path'),
    );
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    final mimeType = await _detectMimeType(filePath);
    final extension = _imageExtensions[mimeType];
    request.files.add(await http.MultipartFile.fromPath(
      fieldName,
      filePath,
      // Without these, package:http labels every file application/octet-stream
      // and the name can disagree with the bytes (image_picker keeps the
      // original name after re-encoding a photo).
      contentType: mimeType == null ? null : MediaType.parse(mimeType),
      filename: extension == null ? null : 'report_photo.$extension',
    ));
    return http.Response.fromStream(
      await _client.send(request).timeout(_requestTimeout),
    );
  }

  Future<String?> _detectMimeType(String filePath) async {
    final header = await File(filePath)
        .openRead(0, defaultMagicNumbersMaxLength)
        .expand((bytes) => bytes)
        .toList();
    return lookupMimeType(filePath, headerBytes: header);
  }

  Map<String, String> _headers(String? token) {
    return {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  dynamic decode(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } catch (_) {
      return response.body;
    }
  }

  void ensureSuccess(http.Response response, {String fallback = 'Request failed'}) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final data = decode(response);
      throw ApiException(
        readableError(data, fallback),
        statusCode: response.statusCode,
      );
    }
  }

  String readableError(dynamic data, String fallback) {
    if (data is Map<String, dynamic>) {
      for (final key in ['detail', 'message', 'non_field_errors']) {
        final value = data[key];
        if (value != null) return _valueToMessage(value);
      }
      final messages = <String>[];
      data.forEach((key, value) {
        messages.add('$key: ${_valueToMessage(value)}');
      });
      if (messages.isNotEmpty) return messages.join('\n');
    }
    // Django serves HTML for errors raised outside the API views.
    if (data is String && data.trim().isNotEmpty && !data.trimLeft().startsWith('<')) {
      return data;
    }
    return fallback;
  }

  String _valueToMessage(dynamic value) {
    if (value is List) return value.map((item) => item.toString()).join(' ');
    return value.toString();
  }
}
