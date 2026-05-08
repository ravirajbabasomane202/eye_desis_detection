class PredictionResult {
  final String predictionId;
  final String timestamp;
  final String imageName;
  final String eyeType;
  final String? patientId;
  final String predictedClass;
  final String fullName;
  final double confidence;
  final String severity;
  final String color;
  final String description;
  final String recommendation;
  final List<String> symptoms;
  final bool duplicateWarning;
  final bool lowConfidence;
  final String? confidenceWarning;
  final QualityAssessment? quality;
  final Map<String, double> probabilities;
  final ModelBreakdown? modelBreakdown;

  PredictionResult({
    required this.predictionId,
    required this.timestamp,
    required this.imageName,
    required this.eyeType,
    this.patientId,
    required this.predictedClass,
    required this.fullName,
    required this.confidence,
    required this.severity,
    required this.color,
    required this.description,
    required this.recommendation,
    required this.symptoms,
    required this.duplicateWarning,
    required this.lowConfidence,
    this.confidenceWarning,
    this.quality,
    required this.probabilities,
    this.modelBreakdown,
  });

  factory PredictionResult.fromJson(Map<String, dynamic> json) {
    return PredictionResult(
      predictionId: json['prediction_id'] ?? '',
      timestamp: json['timestamp'] ?? '',
      imageName: json['image_name'] ?? '',
      eyeType: json['eye_type'] ?? 'fundus',
      patientId: json['patient_id'] as String?,
      predictedClass: json['predicted_class'] ?? '',
      fullName: json['full_name'] ?? json['predicted_class'] ?? '',
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      severity: json['severity'] ?? 'unknown',
      color: json['color'] ?? '#888888',
      description: json['description'] ?? '',
      recommendation: json['recommendation'] ?? '',
      symptoms: List<String>.from(json['symptoms'] ?? const []),
      duplicateWarning: json['duplicate_warning'] == true,
      lowConfidence: json['low_confidence'] == true,
      confidenceWarning: json['confidence_warning'] as String?,
      quality: json['quality'] is Map<String, dynamic>
          ? QualityAssessment.fromJson(json['quality'] as Map<String, dynamic>)
          : null,
      probabilities: Map<String, double>.from(
        (json['probabilities'] ?? const {}).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
      ),
      modelBreakdown: json['model_breakdown'] != null
          ? ModelBreakdown.fromJson(json['model_breakdown'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'prediction_id': predictionId,
    'timestamp': timestamp,
    'image_name': imageName,
    'eye_type': eyeType,
    'patient_id': patientId,
    'predicted_class': predictedClass,
    'full_name': fullName,
    'confidence': confidence,
    'severity': severity,
    'color': color,
    'description': description,
    'recommendation': recommendation,
    'symptoms': symptoms,
    'duplicate_warning': duplicateWarning,
    'low_confidence': lowConfidence,
    'confidence_warning': confidenceWarning,
    if (quality != null) 'quality': quality!.toJson(),
    'probabilities': probabilities,
    if (modelBreakdown != null) 'model_breakdown': modelBreakdown!.toJson(),
  };

  List<MapEntry<String, double>> get sortedProbabilities {
    final entries = probabilities.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  bool get isNormal => predictedClass == 'Normal';
  bool get isHighSeverity => severity == 'high';
  bool get hasPatientLink => patientId?.isNotEmpty == true;
  bool get hasWarnings => duplicateWarning || lowConfidence;

  int get colorValue {
    final hex = color.replaceFirst('#', '');
    return int.parse('FF$hex', radix: 16);
  }
}

class QualityAssessment {
  final bool passed;
  final String reason;
  final List<String> issues;
  final Map<String, dynamic> checks;

  QualityAssessment({
    required this.passed,
    required this.reason,
    required this.issues,
    required this.checks,
  });

  factory QualityAssessment.fromJson(Map<String, dynamic> json) {
    return QualityAssessment(
      passed: json['passed'] == true,
      reason: json['reason']?.toString() ?? '',
      issues: List<String>.from(json['issues'] ?? const []),
      checks: Map<String, dynamic>.from(json['checks'] ?? const {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'passed': passed,
    'reason': reason,
    'issues': issues,
    'checks': checks,
  };
}

class ModelBreakdown {
  final Map<String, double> deepHead;
  final Map<String, double> xgboost;
  final double ensembleDeepWeight;

  ModelBreakdown({
    required this.deepHead,
    required this.xgboost,
    required this.ensembleDeepWeight,
  });

  factory ModelBreakdown.fromJson(Map<String, dynamic> json) {
    return ModelBreakdown(
      deepHead: Map<String, double>.from(
        (json['deep_head'] ?? const {}).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
      ),
      xgboost: Map<String, double>.from(
        (json['xgboost'] ?? const {}).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
      ),
      ensembleDeepWeight: (json['ensemble_deep_weight'] ?? 0.95).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'deep_head': deepHead,
    'xgboost': xgboost,
    'ensemble_deep_weight': ensembleDeepWeight,
  };
}
