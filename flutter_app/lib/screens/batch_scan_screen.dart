import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../services/api_service.dart';

class BatchScanScreen extends StatefulWidget {
  const BatchScanScreen({super.key});
  @override
  State<BatchScanScreen> createState() => _BatchScanScreenState();
}

class _BatchScanScreenState extends State<BatchScanScreen> {
  final _picker = ImagePicker();
  List<XFile> _images = [];
  List<Uint8List?> _previews = [];
  String _eyeType = 'fundus';
  String? _selectedPatientId;
  bool _loading = false;
  Map<String, dynamic>? _batchResult;
  String? _error;

  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage(imageQuality: 90);
    if (picked.isEmpty) return;
    if (picked.length > 20) {
      setState(() => _error = 'Maximum 20 images per batch.');
      return;
    }
    final previews = await Future.wait(
        picked.map((f) => f.readAsBytes().then((b) => b as Uint8List?)));
    setState(() {
      _images = picked;
      _previews = previews;
      _batchResult = null;
      _error = null;
    });
  }

  void _removeImage(int i) {
    setState(() {
      _images.removeAt(i);
      _previews.removeAt(i);
    });
  }

  Future<void> _run() async {
    if (_images.isEmpty) {
      setState(() => _error = 'Please select at least one image.');
      return;
    }
    setState(() { _loading = true; _error = null; _batchResult = null; });
    final appState = context.read<AppState>();
    final api = context.read<ApiService>();
    final res = await api.batchPredict(
      baseUrl: appState.baseUrl,
      imageFiles: _images,
      eyeType: _eyeType,
      patientId: _selectedPatientId,
      authToken: appState.authToken,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        _batchResult = res['data'];
      } else {
        _error = res['error'];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final patients = context.watch<AppState>().patients;

    return Scaffold(
      appBar: AppBar(title: const Text('Batch Scan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A73E8).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF1A73E8).withOpacity(0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, color: Color(0xFF1A73E8), size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Upload up to 20 eye images at once. Each image will be quality-checked and classified.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // Eye type selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2332),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _eyeType,
                isExpanded: true,
                dropdownColor: const Color(0xFF1A2332),
                style: const TextStyle(color: Colors.white),
                items: const [
                  DropdownMenuItem(value: 'fundus', child: Text('Fundus (Retinal)')),
                  DropdownMenuItem(value: 'outer', child: Text('Outer Eye')),
                ],
                onChanged: (v) => setState(() => _eyeType = v!),
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (patients.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2332),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _selectedPatientId,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1A2332),
                  style: const TextStyle(color: Colors.white),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Do not attach to a patient'),
                    ),
                    ...patients.map(
                      (patient) => DropdownMenuItem<String?>(
                        value: patient.patientId,
                        child: Text(patient.name),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _selectedPatientId = value),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Pick button
          OutlinedButton.icon(
            onPressed: _loading ? null : _pickImages,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Select Images'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 14),

          // Image grid
          if (_images.isNotEmpty) ...[
            Text('${_images.length} image${_images.length > 1 ? 's' : ''} selected',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: _images.length,
              itemBuilder: (_, i) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _previews[i] != null
                        ? Image.memory(_previews[i]!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity)
                        : const ColoredBox(color: Color(0xFF1A2332)),
                  ),
                  Positioned(
                    top: 4, right: 4,
                    child: GestureDetector(
                      onTap: () => _removeImage(i),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                            color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ),
            const SizedBox(height: 12),
          ],

          // Run button
          ElevatedButton.icon(
            onPressed: _loading || _images.isEmpty ? null : _run,
            icon: _loading
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.play_arrow_rounded),
            label: Text(_loading ? 'Analysing...' : 'Run Batch Analysis'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),

          // Results
          if (_batchResult != null) ...[
            const SizedBox(height: 24),
            _BatchResults(data: _batchResult!),
          ],
        ],
      ),
    );
  }
}

class _BatchResults extends StatelessWidget {
  final Map<String, dynamic> data;
  const _BatchResults({required this.data});

  @override
  Widget build(BuildContext context) {
    final results = List<Map<String, dynamic>>.from(data['results'] ?? []);
    final total = data['total'] ?? 0;
    final success = data['successful'] ?? 0;
    final failed = data['failed'] ?? 0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Summary
      Row(children: [
        _Chip('$total total', Colors.white38),
        const SizedBox(width: 8),
        _Chip('$success success', Colors.greenAccent),
        const SizedBox(width: 8),
        if (failed > 0) _Chip('$failed failed', Colors.redAccent),
      ]),
      const SizedBox(height: 14),

      ...results.map((r) {
        final ok = r['success'] == true;
        final color = ok
            ? Color(int.parse(
                '0xFF${(r['color'] ?? '#888888').replaceFirst('#', '')}'))
            : Colors.red.shade300;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2332),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: ok ? color.withOpacity(0.3) : Colors.red.withOpacity(0.2),
            ),
          ),
          child: ok ? _SuccessRow(r, color) : _FailRow(r),
        );
      }),
    ]);
  }
}

class _SuccessRow extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color color;
  const _SuccessRow(this.data, this.color);
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
            width: 10, height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(data['image_name'] ?? '—',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              overflow: TextOverflow.ellipsis),
        ),
        Text('${(data['confidence'] as num?)?.toStringAsFixed(1) ?? '—'}%',
            style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 6),
      Text(data['predicted_class'] ?? '—',
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
      if (data['low_confidence'] == true)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: const [
            Icon(Icons.warning_amber, color: Color(0xFFFF8800), size: 14),
            SizedBox(width: 4),
            Text('Low confidence — retake recommended',
                style: TextStyle(color: Color(0xFFFF8800), fontSize: 11)),
          ]),
        ),
      if (data['duplicate_warning'] == true)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: const [
            Icon(Icons.copy, color: Color(0xFF9B59B6), size: 14),
            SizedBox(width: 4),
            Text('Possible duplicate',
                style: TextStyle(color: Color(0xFF9B59B6), fontSize: 11)),
          ]),
        ),
    ]);
  }
}

class _FailRow extends StatelessWidget {
  final Map<String, dynamic> data;
  const _FailRow(this.data);
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(data['image_name'] ?? '—',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              overflow: TextOverflow.ellipsis),
          Text(data['error'] ?? 'Failed',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ]),
      ),
    ]);
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
