import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../models/app_state.dart';
import '../models/prediction_result.dart';
import 'result_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan History'),
        actions: [
          Consumer<AppState>(
            builder: (_, state, __) => state.history.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmClear(context, state),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (_, state, __) {
          if (state.history.isEmpty) {
            return _buildEmpty(context);
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            physics: const BouncingScrollPhysics(),
            itemCount: state.history.length,
            itemBuilder: (context, i) =>
                _HistoryItem(result: state.history[i], index: i),
          );
        },
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFF1A2332),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.history, color: Colors.white24, size: 48),
          ),
          const SizedBox(height: 20),
          const Text('No Scans Yet',
              style: TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Your scan history will appear here',
              style: TextStyle(color: Colors.white38, fontSize: 14)),
        ],
      ).animate().fadeIn(),
    );
  }

  void _confirmClear(BuildContext context, AppState state) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2332),
        title: const Text('Clear History',
            style: TextStyle(color: Colors.white)),
        content: const Text('Delete all scan history?',
            style: TextStyle(color: Colors.white60)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              state.clearHistory();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  final PredictionResult result;
  final int index;

  const _HistoryItem({required this.result, required this.index});

  Color get _color => Color(result.colorValue);

  @override
  Widget build(BuildContext context) {
    String formattedDate = '';
    try {
      final dt = DateTime.parse(result.timestamp);
      formattedDate = DateFormat('MMM dd, yyyy  HH:mm').format(dt.toLocal());
    } catch (_) {
      formattedDate = result.timestamp;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _color.withOpacity(0.25)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ResultScreen(result: result)),
          ),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.remove_red_eye,
                      color: _color, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(result.predictedClass,
                              style: TextStyle(
                                  color: _color,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${result.confidence.toStringAsFixed(1)}%',
                              style: TextStyle(
                                  color: _color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(result.fullName,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.access_time,
                              size: 11, color: Colors.white30),
                          const SizedBox(width: 4),
                          Text(formattedDate,
                              style: const TextStyle(
                                  color: Colors.white30, fontSize: 11)),
                          const SizedBox(width: 10),
                          const Icon(Icons.visibility_outlined,
                              size: 11, color: Colors.white30),
                          const SizedBox(width: 4),
                          Text(result.eyeType,
                              style: const TextStyle(
                                  color: Colors.white30, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.white24, size: 20),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: index * 60));
  }
}