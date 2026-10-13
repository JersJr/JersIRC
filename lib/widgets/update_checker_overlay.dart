import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateCheckerOverlay extends StatefulWidget {
  final Widget child;

  const UpdateCheckerOverlay({super.key, required this.child});

  @override
  State<UpdateCheckerOverlay> createState() => _UpdateCheckerOverlayState();
}

class _UpdateCheckerOverlayState extends State<UpdateCheckerOverlay> {
  Timer? _timer;
  bool _dialogShown = false;
  bool _installing = false;

  static const _releaseApi =
      'https://api.github.com/repos/JersJr/JersIRC/releases/latest';

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
        Uri.parse(_releaseApi),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200 || !mounted) return;
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return;

      final tag = (data['tag_name'] as String? ?? '').trim();
      final assets = data['assets'];
      if (tag.isEmpty || assets is! List) return;

      final apkAsset = assets.whereType<Map<String, dynamic>>().cast<
          Map<String, dynamic>?>().firstWhere(
        (asset) =>
            (asset?['name'] as String? ?? '').toLowerCase() ==
            'app-release.apk',
        orElse: () => null,
      );
      final apkUrl = (apkAsset?['browser_download_url'] as String? ?? '').trim();
      if (apkUrl.isEmpty) return;

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
            'Hay una nueva versión de Parloteo disponible: $latest.\n\n'
            'La versión instalada es ${package.version}.\n\n'
            'Puedes descargarla e iniciar la instalación desde aquí.',
          ),
          actions: [
            TextButton(
              onPressed: _installing
                  ? null
                  : () => Navigator.pop(dialogContext),
              child: const Text('Más tarde'),
            ),
            FilledButton(
              onPressed: _installing
                  ? null
                  : () => _downloadAndInstall(apkUrl, dialogContext),
              child: Text(_installing ? 'Descargando…' : 'Descargar e instalar'),
            ),
          ],
        ),
      );
    } catch (_) {
      // La comprobación no debe interrumpir la conexión IRC si falla internet.
    }
  }

  Future<void> _downloadAndInstall(
    String apkUrl,
    BuildContext dialogContext,
  ) async {
    setState(() => _installing = true);
    try {
      if (dialogContext.mounted) {
        // Se mantiene el aviso abierto mientras se descarga el archivo.
      }
      final response = await http.get(
        Uri.parse(apkUrl),
        headers: const {'Accept': 'application/octet-stream'},
      ).timeout(const Duration(minutes: 3));

      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        throw const HttpException('No se pudo descargar el APK.');
      }

      final directory = await getTemporaryDirectory();
      final apkFile = File('${directory.path}/parloteo-update.apk');
      await apkFile.writeAsBytes(response.bodyBytes, flush: true);

      if (!await apkFile.exists() || await apkFile.length() < 1024) {
        throw const FileSystemException('El archivo APK descargado no es válido.');
      }

      if (dialogContext.mounted) Navigator.pop(dialogContext);
      final result = await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo abrir el instalador: ${result.message}. '
              'Puedes volver a intentarlo desde la próxima comprobación.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar Parloteo: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  String _normalize(String value) {
    var v = value.trim();
    if (v.startsWith('v')) v = v.substring(1);
    final parts = v.split('+');
    final version = parts.first;
    final build = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return '$version+$build';
  }

  int _compare(String a, String b) {
    final aParts = a.split('+');
    final bParts = b.split('+');
    final av = aParts.first.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    final bv = bParts.first.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final left = i < av.length ? av[i] : 0;
      final right = i < bv.length ? bv[i] : 0;
      if (left != right) return left.compareTo(right);
    }
    final aBuild = aParts.length > 1 ? int.tryParse(aParts[1]) ?? 0 : 0;
    final bBuild = bParts.length > 1 ? int.tryParse(bParts[1]) ?? 0 : 0;
    return aBuild.compareTo(bBuild);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
