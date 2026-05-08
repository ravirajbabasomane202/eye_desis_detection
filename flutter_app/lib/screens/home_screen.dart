import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import 'admin_dashboard_screen.dart';
import 'batch_scan_screen.dart';
import 'disease_info_screen.dart';
import 'history_screen.dart';
import 'patient_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final pages = appState.isAdmin
        ? const [
            _HomeTab(),
            AdminDashboardScreen(),
            PatientScreen(),
            SettingsScreen(),
          ]
        : const [
            _HomeTab(),
            HistoryScreen(),
            PatientScreen(),
            SettingsScreen(),
          ];

    final destinations = appState.isAdmin
        ? const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Patients',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ]
        : const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Patients',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ];

    final safeIndex = _currentIndex >= pages.length ? 0 : _currentIndex;

    return Scaffold(
      body: IndexedStack(
        index: safeIndex,
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A2332),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          indicatorColor: const Color(0xFF1A73E8).withOpacity(0.2),
          selectedIndex: safeIndex,
          onDestinationSelected: (index) => setState(() => _currentIndex = index),
          destinations: destinations,
        ),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              _buildHeader(context, appState),
              const SizedBox(height: 32),
              _buildHeroSection(context),
              const SizedBox(height: 28),
              _buildQuickActions(context, appState),
              const SizedBox(height: 28),
              _buildStatsRow(),
              const SizedBox(height: 32),
              _buildSectionTitle('Eye Conditions Detected'),
              const SizedBox(height: 16),
              _buildDiseaseGrid(context),
              const SizedBox(height: 32),
              _buildModelInfoCard(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppState appState) {
    final userLabel = appState.isLoggedIn
        ? '${appState.username ?? 'User'} (${appState.role})'
        : 'Guest mode';

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A73E8), Color(0xFF00BCD4)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.remove_red_eye, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'EyeCheck AI',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              Text(
                userLabel,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: const Color(0xFF1A73E8)),
              ),
            ],
          ),
        ),
        if (appState.isAdmin)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1A73E8).withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'ADMIN',
              style: TextStyle(
                color: Color(0xFF1A73E8),
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
      ],
    ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1);
  }

  Widget _buildHeroSection(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A73E8).withOpacity(0.4),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'AI-Powered Analysis',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Detect Eye\nDiseases Early',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Upload fundus or outer-eye images, link them to patients, and review AI results in one place.',
                      style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              const _EyeAnimation(),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScanScreen()),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1A73E8),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text(
                'Start Eye Scan',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms, delay: 100.ms).slideY(begin: 0.1);
  }

  Widget _buildQuickActions(BuildContext context, AppState appState) {
    final actions = <_QuickAction>[
      _QuickAction(
        label: 'Batch Scan',
        subtitle: 'Upload multiple eye images',
        icon: Icons.layers_outlined,
        color: const Color(0xFF00BCD4),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BatchScanScreen()),
        ),
      ),
      _QuickAction(
        label: 'Patients',
        subtitle: 'Create and manage profiles',
        icon: Icons.people_outline,
        color: const Color(0xFF1A73E8),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PatientScreen()),
        ),
      ),
      _QuickAction(
        label: 'Disease Guide',
        subtitle: 'Learn about AMD, DR, and more',
        icon: Icons.menu_book_outlined,
        color: const Color(0xFF2ECC71),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DiseaseInfoScreen()),
        ),
      ),
      _QuickAction(
        label: appState.isAdmin ? 'Dashboard' : 'History',
        subtitle: appState.isAdmin
            ? 'Review system-wide scan stats'
            : 'Open your previous results',
        icon: appState.isAdmin ? Icons.space_dashboard_outlined : Icons.history,
        color: appState.isAdmin ? const Color(0xFFFFA500) : const Color(0xFF9B59B6),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => appState.isAdmin
                ? const AdminDashboardScreen()
                : const HistoryScreen(),
          ),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Quick Actions'),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.35,
          ),
          itemCount: actions.length,
          itemBuilder: (_, index) {
            final action = actions[index];
            return _QuickActionCard(action: action)
                .animate()
                .fadeIn(delay: Duration(milliseconds: 140 + (index * 60)));
          },
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    final stats = const [
      {'value': '6', 'label': 'Conditions', 'icon': Icons.category_outlined},
      {'value': '~91%', 'label': 'Accuracy', 'icon': Icons.verified_outlined},
      {'value': '11', 'label': 'Features', 'icon': Icons.auto_awesome_outlined},
    ];

    return Row(
      children: stats.asMap().entries.map((entry) {
        final index = entry.key;
        final stat = entry.value;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(left: index > 0 ? 8 : 0, right: index < 2 ? 8 : 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2332),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              children: [
                Icon(
                  stat['icon'] as IconData,
                  color: const Color(0xFF1A73E8),
                  size: 22,
                ),
                const SizedBox(height: 8),
                Text(
                  stat['value'] as String,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  stat['label'] as String,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ).animate().fadeIn(delay: Duration(milliseconds: 220 + (index * 80))),
        );
      }).toList(),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
    );
  }

  Widget _buildDiseaseGrid(BuildContext context) {
    final diseases = const [
      {
        'name': 'AMD',
        'full': 'Macular Degeneration',
        'color': 0xFFFF6B6B,
        'icon': Icons.blur_circular,
      },
      {
        'name': 'Cataract',
        'full': 'Lens Opacity',
        'color': 0xFFFFA500,
        'icon': Icons.circle_outlined,
      },
      {
        'name': 'DR',
        'full': 'Diabetic Retinopathy',
        'color': 0xFFFF4500,
        'icon': Icons.water_drop,
      },
      {
        'name': 'Glaucoma',
        'full': 'Optic Nerve Damage',
        'color': 0xFF9B59B6,
        'icon': Icons.remove_red_eye,
      },
      {
        'name': 'HR',
        'full': 'Hypertensive Retinopathy',
        'color': 0xFFE67E22,
        'icon': Icons.favorite,
      },
      {
        'name': 'Normal',
        'full': 'Healthy Eye',
        'color': 0xFF2ECC71,
        'icon': Icons.check_circle,
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.6,
      ),
      itemCount: diseases.length,
      itemBuilder: (context, index) {
        final disease = diseases[index];
        final color = Color(disease['color'] as int);
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A2332),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DiseaseInfoScreen(
                    initialDisease: disease['name'] as String,
                  ),
                ),
              ),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(disease['icon'] as IconData, color: color, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            disease['name'] as String,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            disease['full'] as String,
                            style: TextStyle(color: color.withOpacity(0.8), fontSize: 10),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ).animate().fadeIn(delay: Duration(milliseconds: 300 + (index * 50)));
      },
    );
  }

  Widget _buildModelInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A2332),
            const Color(0xFF1A2332).withBlue(60),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: Color(0xFF1A73E8), size: 20),
              SizedBox(width: 8),
              Text(
                'Ensemble AI Architecture',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _modelBadge('Swin Transformer', 'Vision Backbone'),
          const SizedBox(height: 8),
          _modelBadge('MaxViT', 'Multi-Axis Attention'),
          const SizedBox(height: 8),
          _modelBadge('FocalNet', 'Focal Modulation'),
          const SizedBox(height: 8),
          _modelBadge('XGBoost', 'Feature-based Classifier'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A73E8).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '95% Deep Head + 5% XGBoost weighted ensemble',
              style: TextStyle(color: Color(0xFF1A73E8), fontSize: 12),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 600.ms);
  }

  Widget _modelBadge(String name, String role) {
    return Row(
      children: [
        const Icon(Icons.arrow_right, color: Color(0xFF00BCD4), size: 18),
        const SizedBox(width: 6),
        Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '- $role',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}

class _QuickAction {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _QuickActionCard extends StatelessWidget {
  final _QuickAction action;

  const _QuickActionCard({required this.action});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2332),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: action.color.withOpacity(0.24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: action.color.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(action.icon, color: action.color),
              ),
              const Spacer(),
              Text(
                action.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                action.subtitle,
                style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EyeAnimation extends StatefulWidget {
  const _EyeAnimation();

  @override
  State<_EyeAnimation> createState() => _EyeAnimationState();
}

class _EyeAnimationState extends State<_EyeAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulse = Tween(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Transform.scale(
        scale: _pulse.value,
        child: Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Colors.white.withOpacity(0.25),
                Colors.white.withOpacity(0.05),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.3 * _pulse.value),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withOpacity(0.15 * _pulse.value),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: const Icon(Icons.remove_red_eye_outlined, color: Colors.white, size: 44),
        ),
      ),
    );
  }
}
