import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class JersStorage {
  static const _serversKey = 'jersirc_servers';
  static const _lastServerKey = 'jersirc_last_server';

  Future<List<SavedServer>> loadServers() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getStringList(_serversKey) ?? const <String>[];
    final servers = <SavedServer>[];

    for (final value in raw) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) {
          servers.add(SavedServer.fromJson(decoded));
        }
      } on FormatException {
        // Ignore one corrupt profile instead of preventing all profiles from loading.
      }
    }

    return servers;
  }

  Future<void> saveServers(List<SavedServer> servers) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _serversKey,
      servers.map((server) => jsonEncode(server.toJson())).toList(),
    );
  }

  Future<void> upsertServer(SavedServer server) async {
    final servers = await loadServers();
    final index = servers.indexWhere((item) => item.name == server.name);
    if (index >= 0) {
      servers[index] = server;
    } else {
      servers.add(server);
    }
    await saveServers(servers);
  }

  Future<void> deleteServer(String name) async {
    final servers = await loadServers();
    servers.removeWhere((server) => server.name == name);
    await saveServers(servers);

    if (await getLastServer() == name) {
      await clearLastServer();
    }
  }

  Future<void> setLastServer(String name) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_lastServerKey, name);
  }

  Future<String?> getLastServer() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_lastServerKey);
  }

  Future<void> clearLastServer() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_lastServerKey);
  }
}
