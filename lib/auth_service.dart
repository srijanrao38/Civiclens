import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'models.dart';

class AuthStorageException implements Exception {
  final String message;

  const AuthStorageException(this.message);

  @override
  String toString() => message;
}

/// Rounds to the 6 decimal places (about 11 cm) the backend stores.
double _roundCoordinate(double value) => double.parse(value.toStringAsFixed(6));

class AuthService {
  static const _accessKey = 'civiclens.accessToken';
  static const _refreshKey = 'civiclens.refreshToken';

  final ApiClient api;
  final FlutterSecureStorage storage;

  AuthService({ApiClient? api, FlutterSecureStorage? storage})
      : api = api ?? ApiClient(),
        storage = storage ?? const FlutterSecureStorage();

  Future<UserProfile> login(String username, String password) async {
    final response = await api.postJson('/api/auth/login/', {
      'username': username,
      'password': password,
    });
    debugPrint('Login API response: HTTP ${response.statusCode}');
    api.ensureSuccess(response, fallback: 'Login failed. Please try again.');
    final data = api.decode(response);
    if (data is! Map<String, dynamic> || data['access'] == null) {
      throw const ApiException('The server did not return a login token.');
    }
    try {
      await _saveTokens(data['access'].toString(), data['refresh']?.toString());
    } catch (error, stackTrace) {
      debugPrint('Secure token storage failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      throw const AuthStorageException(
          'The login succeeded, but this device could not save the session.');
    }
    try {
      final profile = await getProfile();
      debugPrint('Profile request succeeded for authenticated user.');
      return profile;
    } catch (_) {
      await logout();
      rethrow;
    }
  }

  Future<void> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final response = await api.postJson('/api/auth/register/', {
      'username': username,
      'email': email,
      'password': password,
    });
    api.ensureSuccess(response, fallback: 'Registration failed.');
  }

  Future<UserProfile?> restoreSession() async {
    try {
      final access = await storage.read(key: _accessKey);
      final refresh = await storage.read(key: _refreshKey);
      if (access == null || refresh == null) return null;
      return await getProfile();
    } catch (error, stackTrace) {
      debugPrint('Session restore failed; clearing stored session: $error');
      debugPrintStack(stackTrace: stackTrace);
      await logout();
      return null;
    }
  }

  Future<UserProfile> getProfile() async {
    final data = await authorizedJson('GET', '/api/auth/me/');
    if (data is! Map<String, dynamic>) {
      throw const ApiException('The server returned an invalid profile.');
    }
    return UserProfile.fromJson(data);
  }

  Future<List<CivicReport>> getPublicReports() async {
    final data = await authorizedJson('GET', '/api/reports/all/');
    return _reportsFrom(data);
  }

  /// Fetches the logged-out view; never sends a token, even a stale stored one.
  Future<List<CivicReport>> getGuestReports() async {
    final response = await api.get('/api/reports/all/');
    api.ensureSuccess(response, fallback: 'Could not load public reports.');
    return _reportsFrom(api.decode(response));
  }

  Future<List<CivicReport>> getMyReports() async {
    final data = await authorizedJson('GET', '/api/reports/my/');
    return _reportsFrom(data);
  }

  Future<CivicReport> createReport({
    required String title,
    required String description,
    required String issueType,
    required double latitude,
    required double longitude,
    File? photo,
  }) async {
    String? photoUrl;
    if (photo != null) {
      final uploadData = await authorizedUpload('/api/reports/upload-photo/', photo);
      if (uploadData is! Map<String, dynamic> || uploadData['photo'] == null) {
        throw const ApiException('The server did not return the uploaded photo URL.');
      }
      photoUrl = uploadData['photo'].toString();
    }

    final photoField = photoUrl == null
        ? const <String, dynamic>{}
        : <String, dynamic>{'photo': photoUrl};
    final data = await authorizedJson('POST', '/api/reports/', {
      'title': title,
      'description': description,
      'issue_type': issueType,
      'latitude': _roundCoordinate(latitude),
      'longitude': _roundCoordinate(longitude),
      ...photoField,
    });
    if (data is! Map<String, dynamic>) {
      throw const ApiException('The server returned an invalid report.');
    }
    return CivicReport.fromJson(data);
  }

  Future<Map<String, dynamic>> verifyReport(int id, String decision) async {
    final data = await authorizedJson('POST', '/api/reports/$id/verify/', {
      'decision': decision,
    });
    if (data is! Map<String, dynamic>) {
      throw const ApiException('The server returned an invalid verification result.');
    }
    return data;
  }

  Future<dynamic> authorizedJson(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    var access = await storage.read(key: _accessKey);
    if (access == null) throw const ApiException('Your session has expired.');

    var response = await _send(method, path, access, body);
    if (response.statusCode == 401) {
      access = await _refreshAccessToken();
      if (access == null) throw const ApiException('Your session has expired.');
      response = await _send(method, path, access, body);
    }
    api.ensureSuccess(response);
    return api.decode(response);
  }

  Future<dynamic> authorizedUpload(String path, File file) async {
    var access = await storage.read(key: _accessKey);
    if (access == null) throw const ApiException('Your session has expired.');
    var response = await api.postMultipart(path, 'photo', file.path, token: access);
    if (response.statusCode == 401) {
      access = await _refreshAccessToken();
      if (access == null) throw const ApiException('Your session has expired.');
      response = await api.postMultipart(path, 'photo', file.path, token: access);
    }
    api.ensureSuccess(response, fallback: 'Photo upload failed.');
    return api.decode(response);
  }

  Future<void> logout() async {
    await storage.delete(key: _accessKey);
    await storage.delete(key: _refreshKey);
  }

  Future<http.Response> _send(
    String method,
    String path,
    String access,
    Map<String, dynamic>? body,
  ) {
    if (method == 'GET') return api.get(path, token: access);
    return api.postJson(path, body ?? <String, dynamic>{}, token: access);
  }

  Future<String?> _refreshAccessToken() async {
    final refresh = await storage.read(key: _refreshKey);
    if (refresh == null) return null;
    try {
      final response = await api.postJson('/api/auth/login/refresh/', {
        'refresh': refresh,
      });
      api.ensureSuccess(response, fallback: 'Your session has expired.');
      final data = api.decode(response);
      final access = data is Map<String, dynamic> ? data['access']?.toString() : null;
      if (access == null) throw const ApiException('Refresh token was rejected.');
      await storage.write(key: _accessKey, value: access);
      return access;
    } catch (_) {
      await logout();
      return null;
    }
  }

  Future<void> _saveTokens(String access, String? refresh) async {
    await storage.write(key: _accessKey, value: access);
    if (refresh != null && refresh.isNotEmpty) {
      await storage.write(key: _refreshKey, value: refresh);
    }
  }

  List<CivicReport> _reportsFrom(dynamic data) {
    if (data is! List) throw const ApiException('The server returned invalid report data.');
    return data
        .whereType<Map<String, dynamic>>()
        .map(CivicReport.fromJson)
        .toList();
  }
}
