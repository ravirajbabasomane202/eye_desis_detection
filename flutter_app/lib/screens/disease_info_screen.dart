import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../services/api_service.dart';

class DiseaseInfoScreen extends StatefulWidget {
  final String? initialDisease;
  const DiseaseInfoScreen({super.key, this.initialDisease});
  @override
  State<DiseaseInfoScreen> createState() => _DiseaseInfoScreenState();
}

class _DiseaseInfoScreenState extends State<DiseaseInfoScreen> {
  List<Map<String, dynamic>> _diseases = [];
  bool _loading = true;
  String? _error;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDisease;
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final appState = context.read<AppState>();
    final api = context.read<ApiService>();
    final res = await api.getDiseaseInfo(appState.baseUrl);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        _diseases = List<Map<String, dynamic>>.from(res['data']['diseases'] ?? []);
        _selected ??= _diseases.isNotEmpty ? _diseases.first['name'] as String? : null;
      } else {
        _diseases = _fallback();
        _selected ??= _diseases.isNotEmpty ? _diseases.first['name'] as String? : null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Eye Disease Guide')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : Row(
                  children: [
                    // Side list
                    Container(
                      width: 120,
                      color: const Color(0xFF0D1B2A),
                      child: ListView(
                        children: _diseases.map((d) {
                          final name = d['name'] as String;
                          final isSelected = name == _selected;
                          final color = Color(int.parse(
                              '0xFF${(d['color'] ?? '#888888').replaceFirst('#', '')}'));
                          return GestureDetector(
                            onTap: () => setState(() => _selected = name),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 16),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? color.withOpacity(0.15)
                                    : Colors.transparent,
                                border: Border(
                                  left: BorderSide(
                                    color: isSelected ? color : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                              ),
                              child: Text(
                                name,
                                style: TextStyle(
                                  color:
                                      isSelected ? color : Colors.white38,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    // Detail
                    Expanded(
                      child: _selected == null
                          ? const Center(
                              child: Text('Select a disease',
                                  style: TextStyle(color: Colors.white38)))
                          : _DiseaseDetail(
                              data: _diseases.firstWhere(
                                  (d) => d['name'] == _selected,
                                  orElse: () => {})),
                    ),
                  ],
                ),
    );
  }

  List<Map<String, dynamic>> _fallback() => [
    {'name': 'AMD', 'full_name': 'Age-related Macular Degeneration', 'color': '#FF6B6B',
     'severity': 'high', 'description': 'Affects central vision.', 'symptoms': ['Blurred central vision'], 'causes': ['Aging'], 'prevention': ['Regular exams']},
    {'name': 'Cataract', 'full_name': 'Cataract', 'color': '#FFA500',
     'severity': 'medium', 'description': 'Clouding of lens.', 'symptoms': ['Cloudy vision'], 'causes': ['Aging'], 'prevention': ['UV protection']},
    {'name': 'DR', 'full_name': 'Diabetic Retinopathy', 'color': '#FF4500',
     'severity': 'high', 'description': 'Retinal damage from diabetes.', 'symptoms': ['Floaters'], 'causes': ['Diabetes'], 'prevention': ['Blood sugar control']},
    {'name': 'Glaucoma', 'full_name': 'Glaucoma', 'color': '#9B59B6',
     'severity': 'high', 'description': 'Optic nerve damage.', 'symptoms': ['Peripheral vision loss'], 'causes': ['High eye pressure'], 'prevention': ['Eye pressure checks']},
    {'name': 'HR', 'full_name': 'Hypertensive Retinopathy', 'color': '#E67E22',
     'severity': 'medium', 'description': 'Retinal damage from high BP.', 'symptoms': ['Reduced vision'], 'causes': ['Hypertension'], 'prevention': ['BP control']},
    {'name': 'Normal', 'full_name': 'Normal', 'color': '#2ECC71',
     'severity': 'none', 'description': 'No disease detected.', 'symptoms': [], 'causes': [], 'prevention': ['Annual exams']},
  ];
}

class _DiseaseDetail extends StatelessWidget {
  final Map<String, dynamic> data;
  const _DiseaseDetail({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox();
    final color = Color(
        int.parse('0xFF${(data['color'] ?? '#888888').replaceFirst('#', '')}'));
    final symptoms = List<String>.from(data['symptoms'] ?? []);
    final causes = List<String>.from(data['causes'] ?? []);
    final prevention = List<String>.from(data['prevention'] ?? []);
    final severity = data['severity'] as String? ?? '';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Header
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.2),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: const Icon(Icons.remove_red_eye, size: 24, color: Colors.white70),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(data['full_name'] ?? data['name'] ?? '—',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              if (severity.isNotEmpty && severity != 'none')
                Text('Severity: ${severity.toUpperCase()}',
                    style: TextStyle(color: color, fontSize: 12,
                        fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),

        if ((data['description'] ?? '').isNotEmpty) ...[
          Text(data['description'],
              style: const TextStyle(color: Colors.white70, height: 1.6)),
          const SizedBox(height: 16),
        ],

        if ((data['prevalence'] ?? '').isNotEmpty &&
            data['prevalence'] != '—') ...[
          _InfoBox(data['prevalence'] as String, Icons.public, color),
          const SizedBox(height: 16),
        ],

        if (symptoms.isNotEmpty) ...[
          _Section('Symptoms', Icons.sick_outlined, symptoms),
          const SizedBox(height: 16),
        ],
        if (causes.isNotEmpty) ...[
          _Section('Causes', Icons.warning_amber_outlined, causes),
          const SizedBox(height: 16),
        ],
        if (prevention.isNotEmpty) ...[
          _Section('Prevention', Icons.shield_outlined, prevention),
          const SizedBox(height: 16),
        ],

        if ((data['recommendation'] ?? '').isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A73E8).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF1A73E8).withOpacity(0.3)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.medical_services_outlined,
                  color: Color(0xFF1A73E8), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(data['recommendation'],
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13, height: 1.5)),
              ),
            ]),
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> items;
  const _Section(this.title, this.icon, this.items);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 16, color: Colors.white54),
        const SizedBox(width: 6),
        Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
      ]),
      const SizedBox(height: 8),
      ...items.map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('• ',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
              Expanded(
                  child: Text(s,
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 13, height: 1.4))),
            ]),
          )),
    ]);
  }
}

class _InfoBox extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  const _InfoBox(this.text, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: TextStyle(color: color, fontSize: 12)),
        ),
      ]),
    );
  }
}
