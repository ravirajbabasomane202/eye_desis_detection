import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/patient.dart';
import '../services/api_service.dart';
import 'progress_screen.dart';

class PatientScreen extends StatefulWidget {
  const PatientScreen({super.key});
  @override
  State<PatientScreen> createState() => _PatientScreenState();
}

class _PatientScreenState extends State<PatientScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final appState = context.read<AppState>();
    final api = context.read<ApiService>();
    final res = await api.listPatients(
      appState.baseUrl,
      authToken: appState.authToken,
    );
    if (!mounted) return;
    if (res['success'] == true) {
      final list = (res['data']['patients'] as List)
          .map((e) => Patient.fromJson(e as Map<String, dynamic>))
          .toList();
      await appState.setPatients(list);
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final patients = context.watch<AppState>().patients;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patients'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddPatient(context),
        icon: const Icon(Icons.person_add),
        label: const Text('Add Patient'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : patients.isEmpty
              ? _Empty(onAdd: () => _showAddPatient(context))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: patients.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _PatientCard(
                    patient: patients[i],
                    onEdit: () => _showEditPatient(context, patients[i]),
                    onViewProgress: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              ProgressScreen(patientId: patients[i].patientId)),
                    ),
                  ),
                ),
    );
  }

  void _showAddPatient(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A2332),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _PatientForm(),
    );
  }

  void _showEditPatient(BuildContext context, Patient patient) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A2332),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _PatientForm(existing: patient),
    );
  }
}

class _PatientCard extends StatelessWidget {
  final Patient patient;
  final VoidCallback onEdit;
  final VoidCallback onViewProgress;
  const _PatientCard(
      {required this.patient, required this.onEdit, required this.onViewProgress});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2332),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF1A73E8).withOpacity(0.2),
            child: Text(
              patient.name.isNotEmpty ? patient.name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: Color(0xFF1A73E8), fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(patient.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15)),
              const SizedBox(height: 3),
              Text(
                [
                  if (patient.age != null) '${patient.age}y',
                  if (patient.gender.isNotEmpty) patient.gender,
                  if (patient.phone.isNotEmpty) patient.phone,
                ].join(' · '),
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Row(children: [
                if (patient.diabetesHistory)
                  _Badge('Diabetes', Colors.orange),
                if (patient.bpHistory) ...[
                  const SizedBox(width: 6),
                  _Badge('BP', Colors.redAccent),
                ],
              ]),
            ]),
          ),
          Column(children: [
            IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined,
                    color: Colors.white38, size: 20)),
            IconButton(
                onPressed: onViewProgress,
                icon: const Icon(Icons.timeline,
                    color: Color(0xFF1A73E8), size: 20)),
          ]),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onAdd;
  const _Empty({required this.onAdd});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.people_outline, size: 60, color: Colors.white24),
        const SizedBox(height: 14),
        const Text('No patients yet',
            style: TextStyle(color: Colors.white38, fontSize: 16)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.person_add),
          label: const Text('Add Patient'),
        ),
      ]),
    );
  }
}

class _PatientForm extends StatefulWidget {
  final Patient? existing;
  const _PatientForm({this.existing});
  @override
  State<_PatientForm> createState() => _PatientFormState();
}

class _PatientFormState extends State<_PatientForm> {
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _gender = 'Male';
  bool _diabetes = false;
  bool _bp = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final p = widget.existing!;
      _nameCtrl.text = p.name;
      _ageCtrl.text = p.age?.toString() ?? '';
      _phoneCtrl.text = p.phone;
      _gender = p.gender.isNotEmpty ? p.gender : 'Male';
      _diabetes = p.diabetesHistory;
      _bp = p.bpHistory;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _ageCtrl.dispose(); _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final appState = context.read<AppState>();
    final api = context.read<ApiService>();
    final data = {
      'name': _nameCtrl.text.trim(),
      'age': int.tryParse(_ageCtrl.text),
      'gender': _gender,
      'phone': _phoneCtrl.text.trim(),
      'diabetes_history': _diabetes,
      'bp_history': _bp,
    };
    Map<String, dynamic> res;
    if (widget.existing == null) {
      res = await api.createPatient(
        appState.baseUrl,
        data,
        authToken: appState.authToken,
      );
    } else {
      res = await api.updatePatient(
        appState.baseUrl,
        widget.existing!.patientId,
        data,
        authToken: appState.authToken,
      );
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (res['success'] == true) {
      final patient = Patient.fromJson(res['data']);
      if (widget.existing == null) {
        await appState.addPatient(patient);
      } else {
        await appState.updatePatient(patient);
      }
      if (!mounted) return;
      Navigator.pop(context);
    } else {
      setState(() => _error = res['error']);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(widget.existing == null ? 'New Patient' : 'Edit Patient',
              style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white38)),
        ]),
        const SizedBox(height: 16),
        _textField(_nameCtrl, 'Full Name *', Icons.person_outline),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _textField(_ageCtrl, 'Age', Icons.calendar_today,
              keyboardType: TextInputType.number)),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _gender,
              dropdownColor: const Color(0xFF1A2332),
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco('Gender', Icons.wc),
              items: ['Male', 'Female', 'Other'].map((g) =>
                  DropdownMenuItem(value: g, child: Text(g))).toList(),
              onChanged: (v) => setState(() => _gender = v!),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        _textField(_phoneCtrl, 'Phone', Icons.phone_outlined,
            keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _Toggle('Diabetes History', _diabetes,
              (v) => setState(() => _diabetes = v))),
          const SizedBox(width: 12),
          Expanded(child: _Toggle('BP History', _bp,
              (v) => setState(() => _bp = v))),
        ]),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(widget.existing == null ? 'Create Patient' : 'Save Changes'),
          ),
        ),
      ]),
    );
  }

  Widget _textField(TextEditingController c, String label, IconData icon,
      {TextInputType? keyboardType}) {
    return TextField(
      controller: c,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: _inputDeco(label, icon),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white38, size: 18),
        filled: true,
        fillColor: Colors.black.withOpacity(0.2),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.white12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.white12)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF1A73E8), width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      );
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Toggle(this.label, this.value, this.onChanged);
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: value
              ? const Color(0xFF1A73E8).withOpacity(0.15)
              : Colors.black.withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: value
                ? const Color(0xFF1A73E8).withOpacity(0.4)
                : Colors.white12,
          ),
        ),
        child: Row(children: [
          Icon(value ? Icons.check_circle : Icons.radio_button_unchecked,
              color: value ? const Color(0xFF1A73E8) : Colors.white38, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: value ? Colors.white : Colors.white38, fontSize: 12)),
          ),
        ]),
      ),
    );
  }
}
