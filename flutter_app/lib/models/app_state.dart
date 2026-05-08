import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'prediction_result.dart';
import 'patient.dart';

class AppState extends ChangeNotifier {
  List<PredictionResult> _history = [];
  List<Patient> _patients = [];
  String _baseUrl = kIsWeb ? 'https://bookish-space-couscous-4p4rqv767w9cqrgq-5000.app.github.dev' : 'http://10.0.2.2:5000';
  bool _isLoading = false;
  bool _isInitialized = false;

  // Auth state
  String? _authToken;
  String? _username;
  String _role = 'patient'; // 'patient' or 'admin'

  List<PredictionResult> get history => List.unmodifiable(_history);
  List<Patient> get patients => List.unmodifiable(_patients);
  String get baseUrl => _baseUrl;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get authToken => _authToken;
  String? get username => _username;
  String get role => _role;
  bool get isLoggedIn => _authToken?.isNotEmpty == true;
  bool get isAdmin => _role == 'admin';

  AppState() {
    _loadSettings();
  }

 Future<void> _loadSettings() async {
  try {
    final prefs = await SharedPreferences.getInstance();

    const defaultUrl = kIsWeb ? 'https://bookish-space-couscous-4p4rqv767w9cqrgq-5000.app.github.dev' : 'http://10.0.2.2:5000';

    _baseUrl = prefs.getString('base_url') ?? defaultUrl;

    if (kIsWeb &&
        (_baseUrl.contains('10.0.2.2') ||
         _baseUrl.contains('127.0.0.1') ||
         _baseUrl.contains('localhost'))) {
      _baseUrl = defaultUrl;
      await prefs.setString('base_url', _baseUrl);
    }

    _authToken = prefs.getString('auth_token');
    if (_authToken?.isEmpty == true) _authToken = null;

    _username = prefs.getString('username');
    if (_username?.isEmpty == true) _username = null;

    _role = prefs.getString('role') ?? 'patient';

    final historyJson = prefs.getStringList('history') ?? [];
    _history = historyJson
        .map((e) => PredictionResult.fromJson(jsonDecode(e)))
        .toList();

    final patientJson = prefs.getStringList('patients') ?? [];
    _patients = patientJson
        .map((e) => Patient.fromJson(jsonDecode(e)))
        .toList();
  } catch (e, st) {
    debugPrint('Failed to load app settings: $e\n$st');
  } finally {
    _isInitialized = true;
    notifyListeners();
  }
}

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.trim().replaceAll(RegExp(r'/$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('base_url', _baseUrl);
    notifyListeners();
  }

  void setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  // ─── Auth ─────────────────────────────────────────────────────────
  Future<void> setAuth(String token, String username, String role) async {
    _authToken = token;
    _username = username;
    _role = role;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('username', username);
    await prefs.setString('role', role);
    notifyListeners();
  }

  Future<void> logout() async {
    _authToken = null;
    _username = null;
    _role = 'patient';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('username');
    await prefs.remove('role');
    notifyListeners();
  }

  // ─── History ─────────────────────────────────────────────────────
  Future<void> addResult(PredictionResult result) async {
    _history.insert(0, result);
    if (_history.length > 50) _history = _history.sublist(0, 50);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'history',
      _history.map((e) => jsonEncode(e.toJson())).toList(),
    );
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _history = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('history');
    notifyListeners();
  }

  // ─── Patients ─────────────────────────────────────────────────────
  Future<void> addPatient(Patient patient) async {
    _patients.insert(0, patient);
    await _savePatients();
    notifyListeners();
  }

  Future<void> updatePatient(Patient updated) async {
    final idx = _patients.indexWhere((p) => p.patientId == updated.patientId);
    if (idx >= 0) _patients[idx] = updated;
    await _savePatients();
    notifyListeners();
  }

  Future<void> setPatients(List<Patient> patients) async {
    _patients = patients;
    await _savePatients();
    notifyListeners();
  }

  Future<void> _savePatients() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'patients',
      _patients.map((p) => jsonEncode(p.toJson())).toList(),
    );
  }

  Patient? getPatientById(String id) {
    try {
      return _patients.firstWhere((p) => p.patientId == id);
    } catch (_) {
      return null;
    }
  }
}
