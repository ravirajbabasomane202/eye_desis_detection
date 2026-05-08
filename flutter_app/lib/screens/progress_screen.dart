import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../services/api_service.dart';

class ProgressScreen extends StatefulWidget {
  final String patientId;
  const ProgressScreen({super.key, required this.patientId});
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final appState = context.read<AppState>();
    final api = context.read<ApiService>();
    final res = await api.getProgress(
      appState.baseUrl,
      widget.patientId,
      authToken: appState.authToken,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        _data = res['data'];
      } else {
        _error = res['error'];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_data != null
            ? '${_data!['patient']['name']} — Progress'
            : 'Disease Progress'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.timeline_outlined, size: 48, color: Colors.white24),
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.white38)),
                  ]),
                )
              : _ProgressBody(data: _data!),
    );
  }
}

class _ProgressBody extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ProgressBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final patient = data['patient'] as Map<String, dynamic>;
    final timeline = List<Map<String, dynamic>>.from(data['timeline'] ?? []);
    final diseaseMap = Map<String, dynamic>.from(data['disease_counts'] ?? {});
    final progressed = data['progressed'] as bool? ?? false;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Patient card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A73E8), Color(0xFF0A2540)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            CircleAvatar(
              backgroundColor: Colors.white24,
              radius: 24,
              child: Text(
                (patient['name'] as String? ?? '?')[0].toUpperCase(),
                style: const TextStyle(
                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(patient['name'] ?? '—',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                Text(
                  '${data['total_scans']} scans total',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ]),
            ),
            if (progressed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.5)),
                ),
                child: const Text('Changed',
                    style: TextStyle(color: Colors.orange, fontSize: 11)),
              ),
          ]),
        ),
        const SizedBox(height: 20),

        // Summaries
        if (diseaseMap.isNotEmpty) ...[
          const _SectionTitle('Diagnosis Breakdown'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDeco(),
            child: Column(
              children: diseaseMap.entries.map((e) {
                final color = _diseaseColor(e.key);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(e.key,
                            style: const TextStyle(color: Colors.white70, fontSize: 13))),
                    Text('${e.value}×',
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.w700)),
                  ]),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Timeline
        if (timeline.isNotEmpty) ...[
          const _SectionTitle('Scan Timeline'),
          ...timeline.asMap().entries.map((entry) {
            final i = entry.key;
            final scan = entry.value;
            final color = Color(int.parse(
                '0xFF${(scan['color'] ?? '#888888').replaceFirst('#', '')}'));
            final isLast = i == timeline.length - 1;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withOpacity(0.2),
                      border: Border.all(color: color, width: 2),
                    ),
                    child: Center(
                      child: Text('${i + 1}',
                          style: TextStyle(
                              color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  if (!isLast)
                    Container(width: 2, height: 50, color: Colors.white12),
                ]),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: _cardDeco(),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text(scan['predicted_class'] ?? '—',
                                style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                          ),
                          Text(
                            '${(scan['confidence'] as num?)?.toStringAsFixed(1) ?? '—'}%',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          _formatDate(scan['timestamp'] as String? ?? ''),
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                        Text(
                          (scan['eye_type'] as String? ?? '').capitalize(),
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ]),
                    ),
                  ),
                ),
              ],
            );
          }),
        ] else
          Container(
            padding: const EdgeInsets.all(20),
            decoration: _cardDeco(),
            child: const Center(
              child: Text('No scans linked to this patient yet.',
                  style: TextStyle(color: Colors.white38)),
            ),
          ),
      ],
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}  ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  BoxDecoration _cardDeco() => BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      );

  Color _diseaseColor(String d) {
    const map = {
      'AMD': Color(0xFFFF6B6B),
      'Cataract': Color(0xFFFFA500),
      'DR': Color(0xFFFF4500),
      'Glaucoma': Color(0xFF9B59B6),
      'HR': Color(0xFFE67E22),
      'Normal': Color(0xFF2ECC71),
    };
    return map[d] ?? const Color(0xFF888888);
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
      );
}

extension StringExt on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
