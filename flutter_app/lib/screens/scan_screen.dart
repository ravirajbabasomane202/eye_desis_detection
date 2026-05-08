import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../models/patient.dart';
import '../services/api_service.dart';
import 'patient_screen.dart';
import 'result_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  String _eyeType = 'fundus';
  String? _selectedPatientId;
  bool _isLoading = false;
  bool _qualityLoading = false;
  Map<String, dynamic>? _qualityData;
  String? _errorMessage;

  final _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );
      if (picked == null) {
        return;
      }

      final imageBytes = await picked.readAsBytes();
      if (!mounted) {
        return;
      }

      setState(() {
        _selectedImage = picked;
        _selectedImageBytes = imageBytes;
        _qualityData = null;
        _errorMessage = null;
      });

      await _runQualityCheck(picked);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = 'Failed to pick image: $e');
    }
  }

  Future<void> _runQualityCheck([XFile? image]) async {
    final imageFile = image ?? _selectedImage;
    if (imageFile == null) {
      return;
    }

    setState(() {
      _qualityLoading = true;
      _errorMessage = null;
    });

    final appState = context.read<AppState>();
    final apiService = context.read<ApiService>();
    final response = await apiService.qualityCheck(
      baseUrl: appState.baseUrl,
      imageFile: imageFile,
      authToken: appState.authToken,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _qualityLoading = false;
      if (response['success'] == true) {
        _qualityData = Map<String, dynamic>.from(response['data'] as Map);
      } else {
        _qualityData = null;
        _errorMessage = response['error'] ?? 'Quality check failed';
      }
    });
  }

  Future<void> _runAnalysis() async {
    if (_selectedImage == null) {
      setState(() => _errorMessage = 'Please select an image first.');
      return;
    }

    if (_qualityLoading) {
      setState(() => _errorMessage = 'Please wait for the quality check to finish.');
      return;
    }

    final qualityPassed = _qualityData == null || _qualityData?['passed'] == true;
    if (!qualityPassed) {
      setState(() {
        _errorMessage =
            (_qualityData?['reason'] ?? 'Image quality check failed.').toString();
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final appState = context.read<AppState>();
    final apiService = context.read<ApiService>();

    final response = await apiService.predict(
      baseUrl: appState.baseUrl,
      imageFile: _selectedImage!,
      eyeType: _eyeType,
      patientId: _selectedPatientId,
      authToken: appState.authToken,
    );

    if (!mounted) {
      return;
    }

    setState(() => _isLoading = false);

    if (response['success'] == true) {
      final result = response['result'];
      await appState.addResult(result);
      if (!mounted) {
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            result: result,
            sourceImage: _selectedImage,
          ),
        ),
      );
    } else {
      final quality = response['quality'];
      if (quality is Map<String, dynamic>) {
        setState(() => _qualityData = quality);
      }
      setState(() => _errorMessage = response['error'] ?? 'Analysis failed');
    }
  }

  Future<void> _openPatients() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PatientScreen()),
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final patients = context.watch<AppState>().patients;
    final selectedPatient = _resolveSelectedPatient(patients);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Eye Scan'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildImageArea().animate().fadeIn().slideY(begin: 0.1),
            const SizedBox(height: 24),
            _buildEyeTypeSelector().animate().fadeIn(delay: 100.ms),
            const SizedBox(height: 24),
            _buildPatientSelector(patients, selectedPatient)
                .animate()
                .fadeIn(delay: 160.ms),
            const SizedBox(height: 24),
            _buildPickerButtons().animate().fadeIn(delay: 200.ms),
            if (_selectedImage != null) ...[
              const SizedBox(height: 20),
              _buildQualitySection().animate().fadeIn(delay: 260.ms),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              _buildError(),
            ],
            const SizedBox(height: 32),
            _buildAnalyzeButton().animate().fadeIn(delay: 320.ms),
            const SizedBox(height: 24),
            _buildTips().animate().fadeIn(delay: 400.ms),
          ],
        ),
      ),
    );
  }

  Patient? _resolveSelectedPatient(List<Patient> patients) {
    if (_selectedPatientId == null) {
      return null;
    }
    for (final patient in patients) {
      if (patient.patientId == _selectedPatientId) {
        return patient;
      }
    }
    return null;
  }

  Widget _buildImageArea() {
    return GestureDetector(
      onTap: () => _pickImage(ImageSource.gallery),
      child: Container(
        width: double.infinity,
        height: 260,
        decoration: BoxDecoration(
          color: const Color(0xFF1A2332),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _selectedImageBytes != null
                ? const Color(0xFF1A73E8).withOpacity(0.6)
                : Colors.white.withOpacity(0.1),
            width: 2,
          ),
        ),
        child: _selectedImageBytes != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      _selectedImageBytes!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Change',
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A73E8).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_photo_alternate_outlined,
                      color: Color(0xFF1A73E8),
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Tap to select eye image',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'JPG, PNG, BMP supported',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildEyeTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Image Type',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _typeButton(
              'fundus',
              'Fundus',
              'Retinal photo\n(AMD, DR, Glaucoma, HR)',
              Icons.visibility,
            ),
            const SizedBox(width: 12),
            _typeButton(
              'outer',
              'Outer Eye',
              'Slit-lamp photo\n(Cataract)',
              Icons.remove_red_eye_outlined,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPatientSelector(List<Patient> patients, Patient? selectedPatient) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Patient Link',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _openPatients,
                icon: const Icon(Icons.people_outline, size: 16),
                label: const Text('Manage'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Attach this scan to a patient profile so progress and reports stay connected.',
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          if (patients.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.24)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No patient profiles yet. You can still scan now, or create a patient first.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            )
          else
            DropdownButtonFormField<String?>(
              value: selectedPatient?.patientId,
              dropdownColor: const Color(0xFF1A2332),
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration(
                'Optional patient',
                Icons.person_outline,
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Do not attach to a patient'),
                ),
                ...patients.map(
                  (patient) => DropdownMenuItem<String?>(
                    value: patient.patientId,
                    child: Text(
                      '${patient.name}${patient.age != null ? ' (${patient.age})' : ''}',
                    ),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _selectedPatientId = value),
            ),
        ],
      ),
    );
  }

  Widget _typeButton(
    String value,
    String label,
    String subtitle,
    IconData icon,
  ) {
    final selected = _eyeType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _eyeType = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF1A73E8).withOpacity(0.15)
                : const Color(0xFF1A2332),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? const Color(0xFF1A73E8)
                  : Colors.white.withOpacity(0.1),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? const Color(0xFF1A73E8) : Colors.white38,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white60,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: selected ? Colors.white54 : Colors.white30,
                        fontSize: 10,
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickerButtons() {
    return Row(
      children: [
        Expanded(
          child: _outlineButton(
            onTap: () => _pickImage(ImageSource.gallery),
            icon: Icons.photo_library_outlined,
            label: 'Gallery',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _outlineButton(
            onTap: () => _pickImage(ImageSource.camera),
            icon: Icons.camera_alt_outlined,
            label: 'Camera',
          ),
        ),
      ],
    );
  }

  Widget _outlineButton({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2332),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white60, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualitySection() {
    final passed = _qualityData?['passed'] == true;
    final issues = List<String>.from(_qualityData?['issues'] ?? const []);
    final checks = Map<String, dynamic>.from(_qualityData?['checks'] ?? const {});
    final accent = _qualityLoading
        ? const Color(0xFF1A73E8)
        : passed
            ? const Color(0xFF2ECC71)
            : const Color(0xFFFF8800);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _qualityLoading
                    ? Icons.hourglass_top
                    : passed
                        ? Icons.verified_outlined
                        : Icons.warning_amber_rounded,
                color: accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Image Quality Check',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              TextButton(
                onPressed: _qualityLoading ? null : _runQualityCheck,
                child: const Text('Check again'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _qualityLoading
                ? 'Checking focus, brightness, and image suitability...'
                : (_qualityData?['reason']?.toString() ??
                    'Quality status will appear here after selecting an image.'),
            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
          if (!_qualityLoading && checks.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metricChip(
                  'Resolution',
                  checks['resolution']?.toString() ?? '-',
                ),
                _metricChip(
                  'Blur',
                  checks['blur_score']?.toString() ?? '-',
                ),
                _metricChip(
                  'Brightness',
                  checks['brightness']?.toString() ?? '-',
                ),
              ],
            ),
          ],
          if (!_qualityLoading && issues.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...issues.map(
              (issue) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '- ',
                      style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w700),
                    ),
                    Expanded(
                      child: Text(
                        issue,
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyzeButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _runAnalysis,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1A73E8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _isLoading
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  ),
                  SizedBox(width: 14),
                  Text(
                    'Analysing...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.biotech_outlined, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Run AI Analysis',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildTips() {
    final tips = [
      'Ensure the image is in focus and well-lit',
      'For fundus images, the optic disc should be visible',
      'For cataract (outer-eye), ensure the lens or iris is clearly visible',
      'Attach scans to a patient profile if you want progress tracking later',
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_outline, color: Color(0xFFFFC107), size: 18),
              SizedBox(width: 8),
              Text(
                'Tips for best results',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...tips.map(
            (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '- ',
                    style: TextStyle(
                      color: Color(0xFF1A73E8),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      tip,
                      style: const TextStyle(
                        color: Colors.white60,
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

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white38, fontSize: 13),
      prefixIcon: Icon(icon, color: Colors.white38, size: 18),
      filled: true,
      fillColor: Colors.black.withOpacity(0.2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF1A73E8), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }
}
