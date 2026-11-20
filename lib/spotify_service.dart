import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class SpotifyTrack {
  const SpotifyTrack({required this.name, required this.artists, required this.spotifyUrl});
  final String name;
  final String artists;
  final String spotifyUrl;
}

class SpotifyService {
  static const redirectUri = 'https://tracynixx-wq.github.io/player/';
  static const _accessKey = 'spotify_access_token';
  static const _refreshKey = 'spotify_refresh_token';
  static const _expiryKey = 'spotify_token_expiry';
  static const _verifierKey = 'spotify_code_verifier';
  static const _stateKey = 'spotify_oauth_state';
  final http.Client _http = http.Client();

  Future<String> getClientId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('spotify_client_id') ?? '';
  }

  Future<void> connect(String clientId) async {
    if (clientId.trim().isEmpty) throw Exception('Укажи Spotify Client ID.');
    final verifier = _randomString(64);
    final challenge = base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
    final state = _randomString(32);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('spotify_client_id', clientId.trim());
    await prefs.setString(_verifierKey, verifier);
    await prefs.setString(_stateKey, state);
    final uri = Uri.https('accounts.spotify.com', '/authorize', {
      'client_id': clientId.trim(),
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
      'state': state,
      'scope': 'playlist-read-private playlist-read-collaborative',
    });
    if (!await launchUrl(uri, webOnlyWindowName: '_self')) {
      throw Exception('Не удалось открыть Spotify для авторизации.');
    }
  }

  Future<bool> handleRedirect(String clientId) async {
    final params = Uri.base.queryParameters;
    final code = params['code'];
    if (code == null) return false;
    if (params['error'] != null) throw Exception('Авторизация отменена: ${params['error']}');
    final prefs = await SharedPreferences.getInstance();
    final state = prefs.getString(_stateKey);
    final verifier = prefs.getString(_verifierKey);
    if (state == null || verifier == null || params['state'] != state) {
      throw Exception('OAuth state не совпадает. Подключи Spotify повторно.');
    }
    final response = await _http.post(
      Uri.https('accounts.spotify.com', '/api/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': clientId.trim(),
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'code_verifier': verifier,
      },
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(data['error_description'] ?? 'Ошибка получения токена: HTTP ${response.statusCode}');
    }
    await _saveTokens(prefs, data);
    await prefs.remove(_stateKey);
    await prefs.remove(_verifierKey);
    return true;
  }

  Future<void> disconnect() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_expiryKey);
    await prefs.remove(_stateKey);
    await prefs.remove(_verifierKey);
  }

  Future<bool> get isConnected async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_accessKey) ?? '').isNotEmpty;
  }

  Future<List<SpotifyTrack>> importPlaylist(String clientId, String url) async {
    final id = _playlistId(url);
    if (id == null) throw Exception('Ссылка на плейлист некорректна.');
    final token = await _validAccessToken(clientId);
    final result = <SpotifyTrack>[];
    var offset = 0;
    while (true) {
      final uri = Uri.https('api.spotify.com', '/v1/playlists/$id/items', {
        'limit': '50',
        'offset': '$offset',
      });
      final response = await _http.get(uri, headers: {'Authorization': 'Bearer $token'});
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        final apiError = data['error'];
        final detail = apiError is Map ? apiError['message'] : null;
        throw Exception(response.statusCode == 403
            ? 'Spotify разрешает читать содержимое только плейлистов владельца или соавтора.'
            : detail ?? 'Spotify API: HTTP ${response.statusCode}');
      }
      final items = data['items'] as List<dynamic>? ?? const [];
      for (final entry in items) {
        final item = entry is Map ? entry['item'] : null;
        if (item is! Map || item['type'] != 'track') continue;
        final artists = (item['artists'] as List<dynamic>? ?? const [])
            .map((a) => a is Map ? (a['name'] ?? '').toString() : '')
            .where((s) => s.isNotEmpty).join(', ');
        final urls = item['external_urls'] as Map? ?? const {};
        result.add(SpotifyTrack(
          name: (item['name'] ?? 'Без названия').toString(),
          artists: artists,
          spotifyUrl: (urls['spotify'] ?? '').toString(),
        ));
      }
      if (data['next'] == null || items.isEmpty) break;
      offset += items.length;
    }
    return result;
  }

  Future<String> _validAccessToken(String clientId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_accessKey);
    final expiry = prefs.getInt(_expiryKey) ?? 0;
    if (token != null && DateTime.now().millisecondsSinceEpoch < expiry - 60000) return token;
    final refresh = prefs.getString(_refreshKey);
    if (refresh == null) throw Exception('Сначала подключи Spotify.');
    final response = await _http.post(
      Uri.https('accounts.spotify.com', '/api/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'client_id': clientId.trim(), 'grant_type': 'refresh_token', 'refresh_token': refresh},
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) throw Exception('Не удалось обновить токен Spotify.');
    await _saveTokens(prefs, data);
    return prefs.getString(_accessKey)!;
  }

  Future<void> _saveTokens(SharedPreferences prefs, Map<String, dynamic> data) async {
    await prefs.setString(_accessKey, data['access_token'] as String);
    if (data['refresh_token'] is String) await prefs.setString(_refreshKey, data['refresh_token'] as String);
    final seconds = (data['expires_in'] as num?)?.toInt() ?? 3600;
    await prefs.setInt(_expiryKey, DateTime.now().millisecondsSinceEpoch + seconds * 1000);
  }

  String? _playlistId(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host != 'open.spotify.com') return null;
    final parts = uri.pathSegments;
    final index = parts.indexOf('playlist');
    if (index < 0 || index + 1 >= parts.length) return null;
    final id = parts[index + 1];
    return RegExp(r'^[A-Za-z0-9]+$').hasMatch(id) ? id : null;
  }

  String _randomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
  }

  void dispose() => _http.close();
}
