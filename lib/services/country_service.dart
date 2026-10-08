import 'dart:convert';
import 'package:http/http.dart' as http;

class DetectedCountry {
  final String name;
  final String code;

  const DetectedCountry({required this.name, required this.code});
}

class CountryService {
  static Future<DetectedCountry?> detect() async {
    try {
      final response = await http
          .get(Uri.parse('https://ipwho.is/'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data is! Map || data['success'] == false) return null;
      final name = data['country']?.toString().trim() ?? '';
      final code = data['country_code']?.toString().trim().toUpperCase() ?? '';
      if (name.isEmpty) return null;
      return DetectedCountry(name: name, code: code);
    } catch (_) {
      return null;
    }
  }
}
