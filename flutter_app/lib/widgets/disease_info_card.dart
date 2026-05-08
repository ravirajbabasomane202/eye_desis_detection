import 'package:flutter/material.dart';

class DiseaseInfoCard extends StatelessWidget {
  final String name;
  final String fullName;
  final Color color;
  final IconData icon;
  final List<String> symptoms;

  const DiseaseInfoCard({
    super.key,
    required this.name,
    required this.fullName,
    required this.color,
    required this.icon,
    required this.symptoms,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                  Text(fullName,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                ],
              ),
            ],
          ),
          if (symptoms.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...symptoms.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.only(top: 6, right: 8),
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle),
                    ),
                    Expanded(
                      child: Text(s,
                          style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                              height: 1.4)),
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
}