import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../services/api_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final appState = context.read<AppState>();
    final api = context.read<ApiService>();
    final res = await api.getAdminDashboard(
      appState.baseUrl,
      authToken: appState.authToken,
    );
    if (!mounted) {
      return;
    }
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
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _load)
              : _DashboardBody(data: _data!, onRefresh: _load),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  final Map<String, dynamic> data;
  final Future<void> Function() onRefresh;

  const _DashboardBody({
    required this.data,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final diseaseMap = Map<String, dynamic>.from(data['disease_counts'] ?? const {});
    final avgConfidence = Map<String, dynamic>.from(data['avg_confidence'] ?? const {});
    final recent = List<Map<String, dynamic>>.from(data['recent_predictions'] ?? const []);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _StatCard(
                'Total Scans',
                data['total_scans']?.toString() ?? '0',
                Icons.document_scanner,
                const Color(0xFF1A73E8),
              ),
              const SizedBox(width: 12),
              _StatCard(
                'Patients',
                data['total_patients']?.toString() ?? '0',
                Icons.people,
                const Color(0xFF00BCD4),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatCard(
                'Low Confidence',
                data['low_confidence_scans']?.toString() ?? '0',
                Icons.warning_amber,
                const Color(0xFFFF8800),
              ),
              const SizedBox(width: 12),
              _StatCard(
                'Duplicates',
                data['duplicate_scans']?.toString() ?? '0',
                Icons.copy,
                const Color(0xFF9B59B6),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionTitle('System Status'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Row(
              children: [
                Icon(
                  data['models_loaded'] == true ? Icons.check_circle : Icons.error,
                  color: data['models_loaded'] == true
                      ? Colors.greenAccent
                      : Colors.redAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['models_loaded'] == true
                            ? 'Models Loaded'
                            : 'Models Not Loaded',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Device: ${data['device'] ?? '-'}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Disease Distribution'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: diseaseMap.isEmpty
                ? const Text(
                    'No predictions yet.',
                    style: TextStyle(color: Colors.white54),
                  )
                : Column(
                    children: diseaseMap.entries.map((entry) {
                      final total = data['total_scans'] as int? ?? 1;
                      final ratio = total > 0 ? (entry.value as int) / total : 0.0;
                      final avg = avgConfidence[entry.key];
                      final color = _diseaseColor(entry.key);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  entry.key,
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                                Text(
                                  '${entry.value} scans${avg is num ? '  |  avg ${avg.toStringAsFixed(1)}%' : ''}',
                                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: ratio.toDouble(),
                                backgroundColor: Colors.white12,
                                valueColor: AlwaysStoppedAnimation<Color>(color),
                                minHeight: 8,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Recent Predictions'),
          if (recent.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _cardDecoration(),
              child: const Text(
                'No scans yet. Recent predictions will appear here after uploads.',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ...recent.map(_RecentPredictionCard.new),
        ],
      ),
    );
  }

  static BoxDecoration _cardDecoration() => BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      );

  static Color _diseaseColor(String disease) {
    const map = {
      'AMD': Color(0xFFFF6B6B),
      'Cataract': Color(0xFFFFA500),
      'DR': Color(0xFFFF4500),
      'Glaucoma': Color(0xFF9B59B6),
      'HR': Color(0xFFE67E22),
      'Normal': Color(0xFF2ECC71),
    };
    return map[disease] ?? const Color(0xFF888888);
  }
}

class _RecentPredictionCard extends StatelessWidget {
  final Map<String, dynamic> prediction;

  const _RecentPredictionCard(this.prediction);

  @override
  Widget build(BuildContext context) {
    final color = Color(
      int.parse('0xFF${(prediction['color'] ?? '#888888').replaceFirst('#', '')}'),
    );
    final confidence = prediction['confidence'];
    final confidenceText = confidence is num ? '${confidence.toStringAsFixed(1)}%' : '-';
    final patientName = (prediction['patient_name'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _DashboardBody._cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prediction['predicted_class']?.toString() ?? '-',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${prediction['image_name'] ?? ''}  |  $confidenceText',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                if (patientName.isNotEmpty)
                  Text(
                    'Patient: $patientName',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (prediction['low_confidence'] == true)
            const Icon(Icons.warning_amber, color: Color(0xFFFF8800), size: 18),
          if (prediction['duplicate_warning'] == true)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.copy, color: Color(0xFF9B59B6), size: 18),
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2332),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w800),
            ),
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          Text(
            error,
            style: const TextStyle(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
