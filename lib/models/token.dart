class Token {
  final String id;
  final String patientId;
  final DateTime createdAt;
  final int number;

  Token({
    required this.id,
    required this.patientId,
    required this.createdAt,
    required this.number,
  });

  factory Token.fromMap(Map<String, dynamic> map) {
    return Token(
      id: map['id'],
      patientId: map['patientId'],
      createdAt: DateTime.parse(map['createdAt']),
      number: map['number'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'patientId': patientId,
      'createdAt': createdAt.toIso8601String(),
      'number': number,
    };
  }
}