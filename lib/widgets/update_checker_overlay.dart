import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateCheckerOverlay extends StatefulWidget {
  final Widget child;

  const UpdateCheckerOverlay({super.key, required this.child});

  @override
  State<UpdateCheckerOverlay> createState() => _UpdateCheckerOverlayState();
}

class _UpdateCheckerOverlayState extends State<UpdateCheckerOverlay> {
  Timer? _timer;
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    if (!kDebugMode) {
      _timer = Timer(const Duration(seconds: 2), _checkForUpdate);
    }
  }

  Future<void> _checkForUpdate() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/JersJr/JersIRC/releases/latest'),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200 || !mounted) return;
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return;

      final tag = (data['tag_name'] as String? ?? '').trim();
      final releaseUrl = (data['html_url'] as String? ?? '').trim();
      if (tag.isEmpty || releaseUrl.isEmpty) return;

      final package = await PackageInfo.fromPlatform();
      final latest = _normalize(tag);
      final current = _normalize(package.version);
      if (_compare(latest, current) <= 0 || _dialogShown || !mounted) return;

      _dialogShown = true;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Nueva versión disponible'),
          content: Text(
            'Hay una nueva versión de JersIRC disponible: $latest.\n\n'
            'La versión instalada es ${package.version}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Más tarde'),
            ),
            FilledButton(
              onPressed: () async {
                final uri = Uri.tryParse(releaseUrl);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Actualizar'),
            ),
          ],
        ),
      );
    } catch (_) {
      // Update checks are non-blocking; connection failures must not affect IRC.
    }
  }

  String _normalize(String value) {
    var v = value.trim();
    if (v.startsWith('v')) v = v.substring(1);
    return v.split('+').first;
  }

  int _compare(String a, String b) {
    final ap = a.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    final bp = b.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final av = i < ap.length ? ap[i] : 0;
      final bv = i < bp.length ? bp[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
