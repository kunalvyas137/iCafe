enum UserRole { admin, staff }

class AppUser {
  final String id;
  final String email;
  final String name;
  final UserRole role;

  AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
  });

  Map<String, dynamic> toMap() {
    return {'id': id, 'email': email, 'name': name, 'role': role.name};
  }

  factory AppUser.fromMap(Map<String, dynamic> map, String id) {
    return AppUser(
      id: id,
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      role: map['role'] == 'admin' ? UserRole.admin : UserRole.staff,
    );
  }
}
