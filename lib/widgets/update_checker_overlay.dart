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

      final apkAsset = assets.whereType<Map<String, dynamic>>().firstWhere(
        (asset) =>
            (asset['name'] as String? ?? '').toLowerCase() ==
            'app-release.apk',
        orElse: () => <String, dynamic>{},
      );
      final apkUrl =
          (apkAsset['browser_download_url'] as String? ?? '').trim();
      if (apkUrl.isEmpty) return;

      final package = await PackageInfo.fromPlatform();
      final latest = _normalize(tag);
      // package.version omite el sufijo +build; package.buildNumber lo contiene.
      // Comparar solo package.version provocaba que 0.3.1+4 se detectara como
      // actualización cada vez que se abría la aplicación.
      final current = _normalize('${package.version}+${package.buildNumber}');
      if (_compare(latest, current) <= 0 || _dialogShown || !mounted) return;

      _dialogShown = true;
      var downloading = false;
      var progress = 0.0;
      var status = 'Preparando descarga…';
      var downloadedBytes = 0;
      var totalBytes = 0;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Nueva versión disponible'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hay una nueva versión de Parloteo disponible: $latest.\n\n'
                  'La versión instalada es ${package.version}+${package.buildNumber}.',
                ),
                if (downloading) ...[
                  const SizedBox(height: 20),
                  Text(status),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: totalBytes > 0 ? progress : null,
                    minHeight: 7,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    totalBytes > 0
                        ? '${(progress * 100).round()}% · ${_formatBytes(downloadedBytes)} de ${_formatBytes(totalBytes)}'
                        : _formatBytes(downloadedBytes),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: downloading
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: const Text('Más tarde'),
              ),
              FilledButton(
                onPressed: downloading
                    ? null
                    : () => _downloadAndInstall(
                          apkUrl,
                          dialogContext,
                          setDialogState,
                          (value, message, received, total) {
                            setDialogState(() {
                              downloading = true;
                              progress = value;
                              status = message;
                              downloadedBytes = received;
                              totalBytes = total;
                            });
                          },
                        ),
                child: Text(downloading ? 'Descargando…' : 'Actualizar'),
              ),
            ],
          ),
        ),
      );
      _dialogShown = false;
    } catch (_) {
      // La comprobación no debe interrumpir la conexión IRC si falla internet.
    }
  }

  Future<void> _downloadAndInstall(
    String apkUrl,
    BuildContext dialogContext,
    StateSetter setDialogState,
    void Function(double progress, String status, int received, int total)
        onProgress,
  ) async {
    if (_installing) return;
    _installing = true;
    onProgress(0, 'Conectando con GitHub…', 0, 0);

    try {
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(apkUrl))
          ..headers['Accept'] = 'application/octet-stream';
        final response = await client.send(request).timeout(
              const Duration(minutes: 3),
            );

        if (response.statusCode != 200) {
          throw HttpException(
            'GitHub respondió con HTTP ${response.statusCode}.',
          );
        }

        final total = response.contentLength ?? 0;
        final directory = await getTemporaryDirectory();
        final apkFile = File('${directory.path}/parloteo-update.apk');
        final sink = apkFile.openWrite();
        var received = 0;

        onProgress(0, 'Descargando APK…', 0, total);
        try {
          await for (final chunk in response.stream.timeout(
            const Duration(minutes: 3),
          )) {
            sink.add(chunk);
            received += chunk.length;
            onProgress(
              total > 0 ? (received / total).clamp(0.0, 1.0) : 0,
              'Descargando APK…',
              received,
              total,
            );
          }
        } finally {
          await sink.close();
        }

        if (received < 1024 ||
            !await apkFile.exists() ||
            await apkFile.length() < 1024) {
          throw const FileSystemException(
            'El archivo descargado está vacío o no es un APK válido.',
          );
        }

        // Si GitHub no informó el tamaño total, la barra se completa al terminar.
        onProgress(1, 'Descarga completada. Abriendo instalador…', received,
            total > 0 ? total : received);

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
                'Comprueba que Android permita instalar aplicaciones desde esta fuente.',
              ),
            ),
          );
        }
      } finally {
        client.close();
      }
    } catch (error) {
      if (dialogContext.mounted) {
        setDialogState(() {
          // Deja visible el diálogo y permite volver a intentar la descarga.
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar Parloteo: $error')),
        );
      }
    } finally {
      _installing = false;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
