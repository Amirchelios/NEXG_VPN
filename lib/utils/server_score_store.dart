import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum ServerScoreMode { discover, scored }

class ServerScore {
  final String configId;
  final int ping;
  final bool youtubeOk;
  final bool instagramOk;
  final int score;
  final int timestampMs;
  final String country;
  final String city;
  final String countryCode;

  const ServerScore({
    required this.configId,
    required this.ping,
    required this.youtubeOk,
    required this.instagramOk,
    required this.score,
    required this.timestampMs,
    required this.country,
    required this.city,
    required this.countryCode,
  });

  Map<String, dynamic> toJson() => {
        'configId': configId,
        'ping': ping,
        'youtubeOk': youtubeOk,
        'instagramOk': instagramOk,
        'score': score,
        'timestampMs': timestampMs,
        'country': country,
        'city': city,
        'countryCode': countryCode,
      };

  factory ServerScore.fromJson(Map<String, dynamic> json) {
    return ServerScore(
      configId: json['configId'] as String,
      ping: (json['ping'] as num?)?.toInt() ?? -1,
      youtubeOk: json['youtubeOk'] == true,
      instagramOk: json['instagramOk'] == true,
      score: (json['score'] as num?)?.toInt() ?? 0,
      timestampMs: (json['timestampMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      country: json['country'] as String? ?? '',
      city: json['city'] as String? ?? '',
      countryCode: json['countryCode'] as String? ?? '',
    );
  }
}

class ServerScoreStore {
  static const String _scoresKey = 'server_scores';
  static const String _modeKey = 'server_score_mode';
  static const String _badKey = 'bad_servers';

  static int calculateScore({
    required int ping,
    required bool youtubeOk,
    required bool instagramOk,
  }) {
    final int normalizedPing = ping > 0 ? ping : 10000;
    final int pingScore = (1000 - normalizedPing).clamp(0, 1000);
    final int bonus = (youtubeOk ? 300 : 0) + (instagramOk ? 300 : 0);
    return pingScore + bonus;
  }

  static Future<Map<String, ServerScore>> loadScores() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_scoresKey);
    if (jsonString == null || jsonString.isEmpty) {
      return {};
    }

    try {
      final Map<String, dynamic> data = jsonDecode(jsonString);
      return data.map(
        (key, value) =>
            MapEntry(key, ServerScore.fromJson(value as Map<String, dynamic>)),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<ServerScore?> getScore(String configId) async {
    final scores = await loadScores();
    return scores[configId];
  }

  static Future<void> saveScore(ServerScore score) async {
    final prefs = await SharedPreferences.getInstance();
    final scores = await loadScores();
    scores[score.configId] = score;
    final jsonString = jsonEncode(
      scores.map((key, value) => MapEntry(key, value.toJson())),
    );
    await prefs.setString(_scoresKey, jsonString);
  }

  static Future<void> removeScore(String configId) async {
    final prefs = await SharedPreferences.getInstance();
    final scores = await loadScores();
    if (!scores.containsKey(configId)) {
      return;
    }
    scores.remove(configId);
    final jsonString = jsonEncode(
      scores.map((key, value) => MapEntry(key, value.toJson())),
    );
    await prefs.setString(_scoresKey, jsonString);
  }

  static Future<bool> hasScores() async {
    final scores = await loadScores();
    return scores.isNotEmpty;
  }

  static Future<ServerScoreMode> loadMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_modeKey);
    if (value == 'scored') {
      return ServerScoreMode.scored;
    }
    return ServerScoreMode.discover;
  }

  static Future<void> saveMode(ServerScoreMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _modeKey,
      mode == ServerScoreMode.scored ? 'scored' : 'discover',
    );
  }

  static Future<Set<String>> loadBadServerIds() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_badKey);
    if (jsonString == null || jsonString.isEmpty) {
      return {};
    }
    try {
      final List<dynamic> data = jsonDecode(jsonString);
      return data.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> addBadServer(String configId) async {
    final prefs = await SharedPreferences.getInstance();
    final badIds = await loadBadServerIds();
    badIds.add(configId);
    await prefs.setString(_badKey, jsonEncode(badIds.toList()));
  }

  static Future<void> removeBadServer(String configId) async {
    final prefs = await SharedPreferences.getInstance();
    final badIds = await loadBadServerIds();
    if (!badIds.remove(configId)) {
      return;
    }
    await prefs.setString(_badKey, jsonEncode(badIds.toList()));
  }
}
