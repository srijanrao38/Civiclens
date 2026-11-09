class UserProfile {
  final int id;
  final String username;
  final String email;
  final String role;
  final int points;
  final bool isOfficialApproved;

  const UserProfile({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    required this.points,
    required this.isOfficialApproved,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: _asInt(json['id']),
      username: _asString(json['username']),
      email: _asString(json['email']),
      role: _asString(json['role'], fallback: 'CITIZEN'),
      points: _asInt(json['points']),
      isOfficialApproved: json['is_official_approved'] == true,
    );
  }
}

class CivicReport {
  final int id;
  final String citizen;
  final String title;
  final String description;
  final String issueType;
  final double latitude;
  final double longitude;
  final String? photo;
  final String status;
  final String? verifiedBy;
  final DateTime? createdAt;

  const CivicReport({
    required this.id,
    required this.citizen,
    required this.title,
    required this.description,
    required this.issueType,
    required this.latitude,
    required this.longitude,
    required this.photo,
    required this.status,
    required this.verifiedBy,
    required this.createdAt,
  });

  factory CivicReport.fromJson(Map<String, dynamic> json) {
    return CivicReport(
      id: _asInt(json['id']),
      citizen: _asString(json['citizen']),
      title: _asString(json['title'], fallback: 'Untitled report'),
      description: _asString(json['description']),
      issueType: _asString(json['issue_type'], fallback: 'OTHER'),
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
      photo: _nullableString(json['photo']),
      status: _asString(json['status'], fallback: 'PENDING'),
      verifiedBy: _nullableString(json['verified_by']),
      createdAt: DateTime.tryParse(_asString(json['created_at'])),
    );
  }
}

int _asInt(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;

double _asDouble(dynamic value) =>
    double.tryParse(value?.toString() ?? '') ?? 0;

String _asString(dynamic value, {String fallback = ''}) =>
    value?.toString() ?? fallback;

String? _nullableString(dynamic value) {
  if (value == null || value.toString().isEmpty) return null;
  return value.toString();
}
