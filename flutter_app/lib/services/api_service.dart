import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';


import '../models/prediction_result.dart';

class ApiService {
  Map<String, String> _headers({String? authToken, bool json = false}) {
    final headers = <String, String>{};
    if (json) {
      headers['Content-Type'] = 'application/json';
    }
    if (authToken?.isNotEmpty == true) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    return headers;
  }

  String _errorFromBody(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['error']?.toString() ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<Map<String, dynamic>> healthCheck(String baseUrl) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Server returned ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> predict({
    required String baseUrl,
    required XFile imageFile,
    required String eyeType,
    String? patientId,
    String? authToken,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/predict');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(_headers(authToken: authToken));
      final imageBytes = await imageFile.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: imageFile.name.isNotEmpty ? imageFile.name : 'eye_image.jpg',
      ));
      request.fields['eye_type'] = eyeType;
      if (patientId != null && patientId.isNotEmpty) {
        request.fields['patient_id'] = patientId;
      }

      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'result': PredictionResult.fromJson(data)};
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': false,
        'status_code': response.statusCode,
        'error': body['error'] ?? 'Prediction failed (${response.statusCode})',
        'quality': body['quality'],
      };
    } on http.ClientException catch (e) {
      return {'success': false, 'error': 'Cannot connect to server. ${e.message}'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> batchPredict({
    required String baseUrl,
    required List<XFile> imageFiles,
    required String eyeType,
    String? patientId,
    String? authToken,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/batch-predict');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(_headers(authToken: authToken));
      request.fields['eye_type'] = eyeType;
      if (patientId != null && patientId.isNotEmpty) {
        request.fields['patient_id'] = patientId;
      }
      for (final f in imageFiles) {
        final bytes = await f.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes(
          'images',
          bytes,
          filename: f.name.isNotEmpty ? f.name : 'eye_image.jpg',
        ));
      }
      final streamed = await request.send().timeout(const Duration(seconds: 300));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {
        'success': false,
        'error': _errorFromBody(response, 'Batch analysis failed'),
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> qualityCheck({
    required String baseUrl,
    required XFile imageFile,
    String? authToken,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/quality-check');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(_headers(authToken: authToken));
      final bytes = await imageFile.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: imageFile.name.isNotEmpty ? imageFile.name : 'image.jpg',
      ));
      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': _errorFromBody(response, 'Quality check failed')};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Uint8List?> getGradcam({
    required String baseUrl,
    required XFile imageFile,
    required String eyeType,
    String? authToken,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/gradcam');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(_headers(authToken: authToken));
      final bytes = await imageFile.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: imageFile.name.isNotEmpty ? imageFile.name : 'image.jpg',
      ));
      request.fields['eye_type'] = eyeType;
      final streamed = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> getClasses(String baseUrl) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/classes'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load classes'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getDiseaseInfo(String baseUrl, {String? name}) async {
    try {
      final url = name != null
          ? '$baseUrl/disease-info?name=$name'
          : '$baseUrl/disease-info';
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': 'Failed to load disease information'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getHistory(
    String baseUrl, {
    int limit = 20,
    String? patientId,
    String? authToken,
  }) async {
    try {
      var url = '$baseUrl/history?limit=$limit';
      if (patientId != null) {
        url += '&patient_id=$patientId';
      }
      final response = await http
          .get(Uri.parse(url), headers: _headers(authToken: authToken))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': _errorFromBody(response, 'Failed to load history')};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Uint8List?> downloadReport(
    String baseUrl,
    String predictionId, {
    String? authToken,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/report/$predictionId'),
            headers: _headers(authToken: authToken),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> createPatient(
    String baseUrl,
    Map<String, dynamic> data, {
    String? authToken,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/patients'),
            headers: _headers(authToken: authToken, json: true),
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {
        'success': false,
        'error': _errorFromBody(response, 'Failed to create patient'),
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> listPatients(
    String baseUrl, {
    String? authToken,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/patients'),
            headers: _headers(authToken: authToken),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': _errorFromBody(response, 'Failed to load patients')};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> updatePatient(
    String baseUrl,
    String patientId,
    Map<String, dynamic> data, {
    String? authToken,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/patients/$patientId'),
            headers: _headers(authToken: authToken, json: true),
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': _errorFromBody(response, 'Failed to update patient')};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getProgress(
    String baseUrl,
    String patientId, {
    String? authToken,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/progress/$patientId'),
            headers: _headers(authToken: authToken),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'error': _errorFromBody(response, 'Failed to load progress')};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getAdminDashboard(
    String baseUrl, {
    String? authToken,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/admin/dashboard'),
            headers: _headers(authToken: authToken),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {
        'success': false,
        'error': _errorFromBody(response, 'Failed to load admin dashboard'),
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> login(
    String baseUrl,
    String username,
    String password,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/login'),
            headers: _headers(json: true),
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {
        'success': false,
        'error': _errorFromBody(response, 'Login failed'),
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> register(
    String baseUrl,
    String username,
    String password,
    String role,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/register'),
            headers: _headers(json: true),
            body: jsonEncode({
              'username': username,
              'password': password,
              'role': role,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {
        'success': false,
        'error': _errorFromBody(response, 'Registration failed'),
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
