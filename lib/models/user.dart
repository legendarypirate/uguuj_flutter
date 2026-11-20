// lib/models/user.dart
class User {
  final String id;
  final String phone;
  final String name;
  final String email;

  User({
    required this.id,
    required this.phone,
    required this.name,
    required this.email,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'].toString(),
      phone: json['phone'].toString(),
      name: json['name'].toString(),
      email: json['email'].toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone': phone,
      'name': name,
      'email': email,
    };
  }
}