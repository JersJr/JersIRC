import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class JersStorage {
  static const _serversKey = 'jersirc_servers';
  static const _lastServerKey = 'jersirc_last_server';

  Future<List<SavedServer>> loadServers() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_serversKey) ?? [];
    return raw.map((e) => SavedServer.fromJson(jsonDecode(e) as Map<String, dynamic>)).toList();
  }

  Future<void> saveServers(List<SavedServer> servers) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_serversKey, servers.map((s) => jsonEncode(s.toJson())).toList());
  }

  Future<void> setLastServer(String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_lastServerKey, name);
  }

  Future<String?> getLastServer() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_lastServerKey);
  }
}
