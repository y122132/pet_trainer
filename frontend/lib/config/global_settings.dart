import 'package:shared_preferences/shared_preferences.dart';

class GlobalSettings {
  static bool useEdgeAI = false;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    useEdgeAI = prefs.getBool('useEdgeAI') ?? false;
  }

  static Future<void> setEdgeAI(bool value) async {
    useEdgeAI = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('useEdgeAI', value);
  }
}
