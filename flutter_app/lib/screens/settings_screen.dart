import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/app_state.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlController;
  bool _isTesting = false;
  String? _testResult;
  bool? _testSuccess;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
      text: context.read<AppState>().baseUrl,
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final url = _urlController.text.trim();
    final apiService = context.read<ApiService>();
    final result = await apiService.healthCheck(url);

    if (!mounted) return;

    setState(() {
      _isTesting = false;
      _testSuccess = result['success'] as bool;
      if (result['success'] == true) {
        final data = result['data'] as Map<String, dynamic>;
        final modelsLoaded = data['models_loaded'] as bool? ?? false;
        _testResult = modelsLoaded
            ? '✅ Connected! Models are loaded and ready.'
            : '⚠️ Server reachable but models not loaded yet.';
      } else {
        _testResult = '❌ ${result['error']}';
      }
    });
  }

  Future<void> _saveUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    await context.read<AppState>().setBaseUrl(url);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('API URL saved'),
        backgroundColor: Color(0xFF2ECC71),
      ),
    );
  }

  Future<void> _logout() async {
    await context.read<AppState>().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildApiSection().animate().fadeIn(),
            const SizedBox(height: 24),
            _buildAboutSection().animate().fadeIn(delay: 150.ms),
            const SizedBox(height: 24),
            _buildAccountSection().animate().fadeIn(delay: 300.ms),
            const SizedBox(height: 24),
            _buildDisclaimerCard().animate().fadeIn(delay: 300.ms),
          ],
        ),
      ),
    );
  }

  Widget _buildApiSection() {
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
              Icon(Icons.api, color: Color(0xFF1A73E8), size: 20),
              SizedBox(width: 8),
              Text('API Configuration',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Backend URL',
              style: TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'http://192.168.1.x:5000',
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFF1A73E8), width: 2),
              ),
              prefixIcon:
                  const Icon(Icons.link, color: Colors.white38, size: 18),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'For Flutter Web use http://127.0.0.1:5000\n'
            'For Android emulator use http://10.0.2.2:5000\n'
            'For a real device use your machine\'s local IP',
            style: TextStyle(color: Colors.white30, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (_testResult != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_testSuccess == true)
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (_testSuccess == true)
                      ? Colors.green.withOpacity(0.3)
                      : Colors.red.withOpacity(0.3),
                ),
              ),
              child: Text(_testResult!,
                  style: TextStyle(
                    color: _testSuccess == true ? Colors.green : Colors.red,
                    fontSize: 13,
                  )),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isTesting ? null : _testConnection,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1A73E8),
                    side: const BorderSide(color: Color(0xFF1A73E8)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isTesting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering, size: 16),
                  label: Text(_isTesting ? 'Testing...' : 'Test'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saveUrl,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection() {
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
              Icon(Icons.info_outline, color: Color(0xFF00BCD4), size: 20),
              SizedBox(width: 8),
              Text('About EyeCheck AI',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
            ],
          ),
          const SizedBox(height: 16),
          _infoRow('Version', '1.0.0'),
          _infoRow('AI Models', 'Swin + MaxViT + FocalNet + XGBoost'),
          _infoRow('Conditions', 'AMD, Cataract, DR, Glaucoma, HR, Normal'),
          _infoRow('Ensemble', '95% Deep Head + 5% XGBoost'),
        ],
      ),
    );
  }

  Widget _buildAccountSection() {
    final appState = context.watch<AppState>();
    final isLoggedIn = appState.isLoggedIn;

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
              Icon(Icons.person_outline, color: Color(0xFF1A73E8), size: 20),
              SizedBox(width: 8),
              Text('Account',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            isLoggedIn
                ? 'Signed in as ${appState.username ?? 'User'} (${appState.role})'
                : 'You are currently using the app without logging in.',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (isLoggedIn) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _logout,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('Log Out'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(key,
                style: const TextStyle(color: Colors.white38, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withOpacity(0.25)),
      ),
      child: const Column(
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange, size: 18),
              SizedBox(width: 8),
              Text('Medical Disclaimer',
                  style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ],
          ),
          SizedBox(height: 10),
          Text(
            'EyeCheck AI is an AI screening tool for educational and informational purposes only. '
            'It is NOT a substitute for professional medical advice, diagnosis, or treatment. '
            'Always consult a qualified ophthalmologist or healthcare provider for eye health concerns.',
            style: TextStyle(color: Colors.orange, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }
}
