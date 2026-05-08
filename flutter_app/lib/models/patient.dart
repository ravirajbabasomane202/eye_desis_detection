class Patient {
  final String patientId;
  final String name;
  final int? age;
  final String gender;
  final String phone;
  final bool diabetesHistory;
  final bool bpHistory;
  final String createdAt;

  Patient({
    required this.patientId,
    required this.name,
    this.age,
    required this.gender,
    required this.phone,
    required this.diabetesHistory,
    required this.bpHistory,
    required this.createdAt,
  });

  factory Patient.fromJson(Map<String, dynamic> json) => Patient(
        patientId: json['patient_id'] ?? '',
        name: json['name'] ?? '',
        age: json['age'] as int?,
        gender: json['gender'] ?? '',
        phone: json['phone'] ?? '',
        diabetesHistory: json['diabetes_history'] ?? false,
        bpHistory: json['bp_history'] ?? false,
        createdAt: json['created_at'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'patient_id': patientId,
        'name': name,
        'age': age,
        'gender': gender,
        'phone': phone,
        'diabetes_history': diabetesHistory,
        'bp_history': bpHistory,
        'created_at': createdAt,
      };
}