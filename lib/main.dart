import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  runApp(const PlayerApp());
}

class PlayerApp extends StatelessWidget {
  const PlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B5CF6),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF101014),
        useMaterial3: true,
      ),
      home: const PlayerHome(),
    );
  }
}

class PlayerHome extends StatefulWidget {
  const PlayerHome({super.key});

  @override
  State<PlayerHome> createState() => _PlayerHomeState();
}

class _PlayerHomeState extends State<PlayerHome> {
  final AudioPlayer _player = AudioPlayer();
  final TextEditingController _spotifyController = TextEditingController();
  String? _trackName;
  String _status = 'Выберите аудиофайл для проверки воспроизведения';
  String? _playlistId;
  bool _busy = false;

  Future<void> _pickAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      if (file.path == null) {
        setState(() => _status = 'Не удалось получить путь к файлу');
        return;
      }

      await _player.setFilePath(file.path!);
      await _player.play();
      if (!mounted) return;
      setState(() {
        _trackName = file.name;
        _status = 'Файл загружен и воспроизводится';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Ошибка воспроизведения: $error');
    }
  }

  void _checkSpotifyLink() {
    final input = _spotifyController.text.trim();
    final uri = Uri.tryParse(input);
    final segments = uri?.pathSegments ?? const <String>[];
    final playlistIndex = segments.indexOf('playlist');

    if (uri == null ||
        uri.host != 'open.spotify.com' ||
        playlistIndex < 0 ||
        playlistIndex + 1 >= segments.length ||
        !RegExp(r'^[A-Za-z0-9]+$').hasMatch(segments[playlistIndex + 1])) {
      setState(() {
        _playlistId = null;
        _status = 'Некорректная ссылка. Нужна ссылка на плейлист Spotify.';
      });
      return;
    }

    setState(() {
      _playlistId = segments[playlistIndex + 1];
      _status = 'Ссылка распознана. Получение списка треков подключим через Spotify API.';
    });
  }

  @override
  void dispose() {
    _spotifyController.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PLAYER'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF1D1B24),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.graphic_eq, size: 38, color: Color(0xFFB69CFF)),
                  const SizedBox(height: 24),
                  Text(
                    _trackName ?? 'Ничего не воспроизводится',
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(_status, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 22),
                  StreamBuilder<PlayerState>(
                    stream: _player.playerStateStream,
                    builder: (context, snapshot) {
                      final playing = snapshot.data?.playing ?? false;
                      return Row(
                        children: [
                          IconButton.filled(
                            onPressed: _trackName == null
                                ? null
                                : () => playing ? _player.pause() : _player.play(),
                            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                            iconSize: 30,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: StreamBuilder<Duration>(
                              stream: _player.positionStream,
                              builder: (context, positionSnapshot) {
                                final position = positionSnapshot.data ?? Duration.zero;
                                final duration = _player.duration ?? Duration.zero;
                                final max = duration.inMilliseconds.toDouble();
                                final value = max <= 0
                                    ? 0.0
                                    : position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble();
                                return Column(
                                  children: [
                                    Slider(
                                      value: value,
                                      max: max <= 0 ? 1 : max,
                                      onChanged: max <= 0
                                          ? null
                                          : (v) => _player.seek(
                                                Duration(milliseconds: v.round()),
                                              ),
                                    ),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(_format(position)),
                                        Text(_format(duration)),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _pickAudio,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Выбрать аудиофайл'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Импорт плейлиста', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            TextField(
              controller: _spotifyController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'Вставьте ссылку Spotify',
                prefixIcon: const Icon(Icons.link),
                filled: true,
                fillColor: const Color(0xFF1D1B24),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _checkSpotifyLink,
                child: const Text('Проверить ссылку'),
              ),
            ),
            if (_playlistId != null) ...[
              const SizedBox(height: 12),
              SelectableText('ID плейлиста: $_playlistId'),
            ],
            const SizedBox(height: 28),
            const Text(
              'Тестовая версия: локальное воспроизведение и распознавание ссылок Spotify. '
              'Для загрузки названий треков потребуется зарегистрированное Spotify-приложение '
              'и доступ к Spotify Web API.',
              style: TextStyle(color: Colors.white54, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  String _format(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
