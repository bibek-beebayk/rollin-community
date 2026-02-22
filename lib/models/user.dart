class User {
  final int id;
  final String username;
  final String email;
  final String userType;
  final bool isVerified;
  final String verificationStatus;
  final String? avatar;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.userType,
    required this.isVerified,
    required this.verificationStatus,
    this.avatar,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    print('DEBUG parsing User fromJson: $json');
    return User(
      id: _parseInt(json['id']) ?? 0,
      username: json['username'] ?? 'Unknown',
      email: json['email'] ?? '',
      userType: json['user_type'] ?? 'client',
      isVerified: json['is_verified'] ?? false,
      verificationStatus: json['verification_status'] ?? 'none',
      avatar: json['avatar'],
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'user_type': userType,
      'is_verified': isVerified,
      'verification_status': verificationStatus,
      'avatar': avatar,
    };
  }

  bool get isStaff => userType == 'staff';
  bool get isAgent => userType == 'agent';
}
