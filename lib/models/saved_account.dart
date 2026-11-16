class SavedAccount {
  final String id;
  final String email;
  final String? password;
  final String? firstName;
  final String? lastName;
  final String? profilePictureUrl;
  final DateTime lastLoginDate;

  SavedAccount({
    required this.id,
    required this.email,
    this.password,
    this.firstName,
    this.lastName,
    this.profilePictureUrl,
    required this.lastLoginDate,
  });

  // Convert SavedAccount to Map for database storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'password': password,
      'first_name': firstName,
      'last_name': lastName,
      'profile_picture_url': profilePictureUrl,
      'last_login_date': lastLoginDate.toIso8601String(),
    };
  }

  // Create SavedAccount from database Map
  factory SavedAccount.fromMap(Map<String, dynamic> map) {
    return SavedAccount(
      id: map['id'] as String,
      email: map['email'] as String,
      password: map['password'] as String?,
      firstName: map['first_name'] as String?,
      lastName: map['last_name'] as String?,
      profilePictureUrl: map['profile_picture_url'] as String?,
      lastLoginDate: DateTime.parse(map['last_login_date'] as String),
    );
  }

  // Get display name for UI
  String get displayName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    } else if (firstName != null) {
      return firstName!;
    }
    return email;
  }

  // Get initials for avatar
  String get initials {
    if (firstName != null && lastName != null) {
      return '${firstName![0]}${lastName![0]}'.toUpperCase();
    } else if (firstName != null) {
      return firstName![0].toUpperCase();
    }
    return email[0].toUpperCase();
  }

  // Copy with method for updates
  SavedAccount copyWith({
    String? id,
    String? email,
    String? password,
    String? firstName,
    String? lastName,
    String? profilePictureUrl,
    DateTime? lastLoginDate,
  }) {
    return SavedAccount(
      id: id ?? this.id,
      email: email ?? this.email,
      password: password ?? this.password,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      profilePictureUrl: profilePictureUrl ?? this.profilePictureUrl,
      lastLoginDate: lastLoginDate ?? this.lastLoginDate,
    );
  }
}
