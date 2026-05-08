import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../models/patient.dart';
import '../models/prediction_result.dart';
import '../services/api_service.dart';
import 'disease_info_screen.dart';
import 'progress_screen.dart';
import 'scan_screen.dart';

class ResultScreen extends StatefulWidget {
  final PredictionResult result;
  final XFile? sourceImage;

  const ResultScreen({
    super.key,
    required this.result,
    this.sourceImage,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  Uint8List? _heatmapBytes;
  bool _loadingHeatmap = false;
  bool _loadingReport = false;

  PredictionResult get result => widget.result;
  Color get _color => Color(result.colorValue);

  Future<void> _loadHeatmap() async {
    if (widget.sourceImage == null || _loadingHeatmap) {
      return;
    }

    setState(() => _loadingHeatmap = true);
    final appState = context.read<AppState>();
    final api = context.read<ApiService>();
    final bytes = await api.getGradcam(
      baseUrl: appState.baseUrl,
      imageFile: widget.sourceImage!,
      eyeType: result.eyeType,
      authToken: appState.authToken,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _loadingHeatmap = false;
      _heatmapBytes = bytes;
    });

    if (bytes == null) {
      _showSnackBar('Heatmap could not be generated for this scan.');
    }
  }

  Future<void> _fetchReport() async {
    if (_loadingReport) {
      return;
    }

    setState(() => _loadingReport = true);
    final appState = context.read<AppState>();
    final api = context.read<ApiService>();
    final pdfBytes = await api.downloadReport(
      appState.baseUrl,
      result.predictionId,
      authToken: appState.authToken,
    );

    if (!mounted) {
      return;
    }

    setState(() => _loadingReport = false);

    if (pdfBytes == null) {
      _showSnackBar('PDF report could not be fetched from the server.');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2332),
        title: const Text(
          'PDF Report Ready',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'The backend generated the scan report successfully.\n\n'
          'Prediction ID: ${result.predictionId}\n'
          'Report size: ${(pdfBytes.length / 1024).toStringAsFixed(1)} KB',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final patient = result.hasPatientLink
        ? context.read<AppState>().getPatientById(result.patientId!)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis Result'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPredictionCard().animate().fadeIn().slideY(begin: 0.1),
            if (result.hasWarnings) ...[
              const SizedBox(height: 16),
              _buildWarningsCard().animate().fadeIn(delay: 80.ms),
            ],
            if (patient != null) ...[
              const SizedBox(height: 16),
              _buildPatientCard(patient).animate().fadeIn(delay: 120.ms),
            ],
            if (result.quality != null) ...[
              const SizedBox(height: 16),
              _buildQualityCard().animate().fadeIn(delay: 160.ms),
            ],
            const SizedBox(height: 20),
            _buildActionStrip(patient).animate().fadeIn(delay: 220.ms),
            if (_heatmapBytes != null) ...[
              const SizedBox(height: 20),
              _buildHeatmapCard().animate().fadeIn(delay: 260.ms),
            ],
            const SizedBox(height: 20),
            _buildConfidenceBar().animate().fadeIn(delay: 300.ms),
            const SizedBox(height: 20),
            _buildProbabilityChart().animate().fadeIn(delay: 360.ms),
            const SizedBox(height: 20),
            _buildProbabilityList().animate().fadeIn(delay: 420.ms),
            if (result.modelBreakdown != null) ...[
              const SizedBox(height: 20),
              _buildModelBreakdown().animate().fadeIn(delay: 480.ms),
            ],
            if (!result.isNormal) ...[
              const SizedBox(height: 20),
              _buildSymptomsCard().animate().fadeIn(delay: 540.ms),
            ],
            const SizedBox(height: 20),
            _buildRecommendation().animate().fadeIn(delay: 600.ms),
            const SizedBox(height: 32),
            _buildBottomActions(context).animate().fadeIn(delay: 660.ms),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildPredictionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _color.withOpacity(0.25),
            _color.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _color.withOpacity(0.4), width: 2),
        boxShadow: [
          BoxShadow(
            color: _color.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _color.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: _color.withOpacity(0.4), width: 2),
            ),
            child: Icon(
              result.isNormal ? Icons.check_circle_outline : Icons.remove_red_eye,
              color: _color,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            result.predictedClass,
            style: TextStyle(
              color: _color,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            result.fullName,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.analytics_outlined, color: _color, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${result.confidence.toStringAsFixed(1)}% Confidence',
                  style: TextStyle(
                    color: _color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _badge(
                result.eyeType == 'fundus' ? 'Fundus' : 'Outer Eye',
                Icons.visibility,
              ),
              const SizedBox(width: 8),
              _badge(_severityLabel(), _severityIcon()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWarningsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
              SizedBox(width: 8),
              Text(
                'Scan Warnings',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (result.lowConfidence)
            Text(
              result.confidenceWarning ?? 'Low confidence. Please retake the image.',
              style: const TextStyle(color: Colors.white70, height: 1.5),
            ),
          if (result.lowConfidence && result.duplicateWarning)
            const SizedBox(height: 8),
          if (result.duplicateWarning)
            const Text(
              'This image also matches a recent scan, so it may be a duplicate upload.',
              style: TextStyle(color: Colors.white70, height: 1.5),
            ),
        ],
      ),
    );
  }

  Widget _buildPatientCard(Patient patient) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: _color.withOpacity(0.2),
            child: Text(
              patient.name.isNotEmpty ? patient.name[0].toUpperCase() : '?',
              style: TextStyle(color: _color, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Linked Patient',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  patient.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [
                    if (patient.age != null) '${patient.age}y',
                    if (patient.gender.isNotEmpty) patient.gender,
                    if (patient.phone.isNotEmpty) patient.phone,
                  ].join('  |  '),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProgressScreen(patientId: patient.patientId),
              ),
            ),
            icon: const Icon(Icons.timeline, color: Color(0xFF1A73E8)),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityCard() {
    final quality = result.quality!;
    final checks = quality.checks;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: quality.passed
              ? const Color(0xFF2ECC71).withOpacity(0.25)
              : Colors.orange.withOpacity(0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                quality.passed ? Icons.verified_outlined : Icons.warning_amber_rounded,
                color: quality.passed ? const Color(0xFF2ECC71) : Colors.orange,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Image Quality Summary',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            quality.reason,
            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
          if (checks.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metricChip('Resolution', checks['resolution']?.toString() ?? '-'),
                _metricChip('Blur', checks['blur_score']?.toString() ?? '-'),
                _metricChip('Brightness', checks['brightness']?.toString() ?? '-'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionStrip(Patient? patient) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Feature Actions',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _actionChip(
              icon: Icons.picture_as_pdf_outlined,
              label: _loadingReport ? 'Loading report...' : 'PDF Report',
              onTap: _loadingReport ? null : _fetchReport,
            ),
            _actionChip(
              icon: Icons.blur_on_outlined,
              label: _loadingHeatmap ? 'Loading heatmap...' : 'Heatmap',
              onTap: widget.sourceImage == null || _loadingHeatmap ? null : _loadHeatmap,
            ),
            _actionChip(
              icon: Icons.menu_book_outlined,
              label: 'Disease Guide',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DiseaseInfoScreen(
                    initialDisease: result.predictedClass,
                  ),
                ),
              ),
            ),
            if (patient != null)
              _actionChip(
                icon: Icons.timeline_outlined,
                label: 'Compare Progress',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProgressScreen(patientId: patient.patientId),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeatmapCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.blur_on_outlined, color: Color(0xFF00BCD4), size: 18),
              SizedBox(width: 8),
              Text(
                'Explainability Heatmap',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'This overlay highlights the regions that most strongly influenced the model output.',
            style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(_heatmapBytes!, fit: BoxFit.cover),
          ),
        ],
      ),
    );
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: onTap == null
                ? Colors.white.withOpacity(0.04)
                : const Color(0xFF1A2332),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: onTap == null ? Colors.white30 : _color, size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: onTap == null ? Colors.white30 : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white54),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _metricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      ),
    );
  }

  String _severityLabel() {
    switch (result.severity) {
      case 'high':
        return 'High Priority';
      case 'medium':
        return 'Moderate';
      case 'none':
        return 'Healthy';
      default:
        return 'Unknown';
    }
  }

  IconData _severityIcon() {
    switch (result.severity) {
      case 'high':
        return Icons.priority_high;
      case 'medium':
        return Icons.warning_amber;
      case 'none':
        return Icons.check;
      default:
        return Icons.help_outline;
    }
  }

  Widget _buildConfidenceBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Confidence Level',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              Text(
                '${result.confidence.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: _color,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: result.confidence / 100),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOut,
              builder: (_, value, __) => LinearProgressIndicator(
                value: value,
                minHeight: 12,
                backgroundColor: Colors.white.withOpacity(0.08),
                valueColor: AlwaysStoppedAnimation(_color),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            result.description,
            style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildProbabilityChart() {
    final sorted = result.sortedProbabilities;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Disease Probability Distribution',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipRoundedRadius: 8,
                    getTooltipItem: (group, _, rod, __) {
                      return BarTooltipItem(
                        '${sorted[group.x].key}\n${rod.toY.toStringAsFixed(1)}%',
                        const TextStyle(color: Colors.white, fontSize: 11),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, _) => Text(
                        '${value.toInt()}%',
                        style: const TextStyle(color: Colors.white38, fontSize: 9),
                      ),
                      interval: 25,
                      reservedSize: 30,
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, _) {
                        final index = value.toInt();
                        if (index >= 0 && index < sorted.length) {
                          return Text(
                            sorted[index].key,
                            style: const TextStyle(color: Colors.white54, fontSize: 9),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: Colors.white.withOpacity(0.05),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: sorted.asMap().entries.map((entry) {
                  final isSelected = entry.value.key == result.predictedClass;
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [
                      BarChartRodData(
                        toY: entry.value.value,
                        color: isSelected ? _color : _color.withOpacity(0.35),
                        width: 22,
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                    ],
                  );
                }).toList(),
                maxY: 100,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProbabilityList() {
    final sorted = result.sortedProbabilities;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'All Class Probabilities',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          ...sorted.asMap().entries.map((entry) {
            final cls = entry.value.key;
            final prob = entry.value.value;
            final isSelected = cls == result.predictedClass;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      cls,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white60,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: prob / 100),
                      duration: Duration(milliseconds: 800 + entry.key * 100),
                      curve: Curves.easeOut,
                      builder: (_, value, __) => ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 8,
                          backgroundColor: Colors.white.withOpacity(0.06),
                          valueColor: AlwaysStoppedAnimation(
                            isSelected ? _color : Colors.white.withOpacity(0.25),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${prob.toStringAsFixed(1)}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: isSelected ? _color : Colors.white38,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildModelBreakdown() {
    final mb = result.modelBreakdown!;
    final deepWeight = mb.ensembleDeepWeight * 100;
    final xgbWeight = (1 - mb.ensembleDeepWeight) * 100;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.psychology_outlined, color: Color(0xFF00BCD4), size: 18),
              SizedBox(width: 8),
              Text(
                'Model Breakdown',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF00BCD4).withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Ensemble = ${deepWeight.toStringAsFixed(0)}% Deep Head + ${xgbWeight.toStringAsFixed(0)}% XGBoost',
              style: const TextStyle(color: Color(0xFF00BCD4), fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _modelColumn(
                  'Deep Head',
                  mb.deepHead,
                  const Color(0xFF1A73E8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _modelColumn(
                  'XGBoost',
                  mb.xgboost,
                  const Color(0xFF9B59B6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modelColumn(String title, Map<String, double> probs, Color color) {
    final sorted = probs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        ...sorted.take(3).map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.key,
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ),
                Text(
                  '${entry.value.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSymptomsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.medical_information_outlined, color: _color, size: 18),
              const SizedBox(width: 8),
              Text(
                'Common Symptoms',
                style: TextStyle(
                  color: _color,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...result.symptoms.map(
            (symptom) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 5, right: 10),
                    decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: Text(
                      symptom,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendation() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            result.isNormal
                ? const Color(0xFF2ECC71).withOpacity(0.12)
                : Colors.orange.withOpacity(0.12),
            const Color(0xFF1A2332),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: result.isNormal
              ? const Color(0xFF2ECC71).withOpacity(0.3)
              : Colors.orange.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.isNormal
                    ? Icons.check_circle_outline
                    : Icons.local_hospital_outlined,
                color: result.isNormal ? const Color(0xFF2ECC71) : Colors.orange,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Recommendation',
                style: TextStyle(
                  color: result.isNormal ? const Color(0xFF2ECC71) : Colors.orange,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            result.recommendation,
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
          ),
          if (!result.isNormal) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withOpacity(0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.red, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This is an AI screening tool. Always consult a qualified ophthalmologist for diagnosis.',
                      style: TextStyle(color: Colors.red, fontSize: 11, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: BorderSide(color: Colors.white.withOpacity(0.2)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.home_outlined, size: 18),
            label: const Text('Home'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScanScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _color,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('New Scan'),
          ),
        ),
      ],
    );
  }
}
