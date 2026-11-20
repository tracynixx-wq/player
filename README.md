# PLAYER

Личный музыкальный плеер на Flutter.

## Текущие функции
- Выбор нескольких локальных аудиофайлов.
- Очередь и переключение треков.
- Воспроизведение, пауза, перемотка и отображение времени.
- Перемешивание и повтор.
- Адаптивный интерфейс для телефона и широкого экрана.
- PWA-манифест и service worker.
- Распознавание Spotify playlist URL. Получение списка треков требует подключения Spotify API.

## Запуск
```bash
flutter pub get
flutter run
```

## Web
```bash
flutter create --platforms=web .
flutter pub get
flutter build web --release --base-href /player/
```

Spotify playlist import требует настройки Spotify Developer API и авторизации. Приложение не загружает аудио Spotify.
