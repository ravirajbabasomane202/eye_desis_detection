import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLogin = true;
  bool _obscure = true;
  bool _loading = false;
  String? _error;
  String _role = 'patient';
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final appState = context.read<AppState>();
    final api = context.read<ApiService>();
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter username and password.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    Map<String, dynamic> res;
    if (_isLogin) {
      res = await api.login(appState.baseUrl, username, password);
    } else {
      res = await api.register(appState.baseUrl, username, password, _role);
    }

    if (!mounted) return;
    setState(() => _loading = false);

    if (res['success'] == true) {
      final data = res['data'];
      await appState.setAuth(data['token'], data['username'], data['role']);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      setState(() => _error = res['error'] ?? 'Unknown error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0D1B2A), Color(0xFF1A2332), Color(0xFF0A2540)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1A73E8), Color(0xFF00BCD4)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1A73E8).withOpacity(0.4),
                            blurRadius: 24,
                            spreadRadius: 4,
                          )
                        ],
                      ),
                      child: const Icon(Icons.remove_red_eye_rounded,
                          color: Colors.white, size: 40),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'EyeCheck AI',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isLogin ? 'Sign in to continue' : 'Create your account',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 36),

                    // Card
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2332),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.07), width: 1),
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          // Toggle
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                _TabBtn('Login', _isLogin,
                                    () => setState(() { _isLogin = true; _error = null; })),
                                _TabBtn('Register', !_isLogin,
                                    () => setState(() { _isLogin = false; _error = null; })),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          _Field(
                            controller: _usernameCtrl,
                            label: 'Username',
                            icon: Icons.person_outline,
                          ),
                          const SizedBox(height: 14),
                          _Field(
                            controller: _passwordCtrl,
                            label: 'Password',
                            icon: Icons.lock_outline,
                            obscure: _obscure,
                            suffix: IconButton(
                              icon: Icon(
                                  _obscure ? Icons.visibility_off : Icons.visibility,
                                  color: Colors.white38, size: 20),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),

                          if (!_isLogin) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _role,
                                  isExpanded: true,
                                  dropdownColor: const Color(0xFF1A2332),
                                  style: const TextStyle(color: Colors.white70),
                                  items: const [
                                    DropdownMenuItem(value: 'patient', child: Text('Patient')),
                                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                                  ],
                                  onChanged: (v) => setState(() => _role = v!),
                                ),
                              ),
                            ),
                          ],

                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.red.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline,
                                      color: Colors.redAccent, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(_error!,
                                        style: const TextStyle(
                                            color: Colors.redAccent, fontSize: 13)),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white),
                                    )
                                  : Text(_isLogin ? 'Sign In' : 'Create Account',
                                      style: const TextStyle(fontSize: 16,
                                          fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const HomeScreen())),
                      child: const Text('Continue without login →',
                          style: TextStyle(color: Colors.white38)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabBtn(this.label, this.active, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF1A73E8) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? Colors.white : Colors.white38,
                fontWeight: active ? FontWeight.w700 : FontWeight.normal,
              )),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.black.withOpacity(0.2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFF1A73E8), width: 1.5),
        ),
      ),
    );
  }
}