# Harmony Music Flow

A fork of [Bikram-Kumar/Harmony-Music](https://github.com/Bikram-Kumar/Harmony-Music), which continues the original [anandnet/Harmony-Music](https://github.com/anandnet/Harmony-Music) project.

Harmony Music is a Flutter music client for Android, Windows, and Linux. This fork adds personalized recommendations and **Harmony Flow**, a continuous queue that mixes your library with new music.

> This fork is unofficial and is not affiliated with or endorsed by the upstream maintainers, YouTube, YouTube Music, Last.fm, or any content provider.

![Harmony Music cover](cover.png)

## Harmony Flow

- Start Flow to keep music playing with a mix of familiar tracks and related discoveries.
- Choose from generated stations when you want a narrower direction.
- Recommendations adapt to listening history, likes, completed tracks, and skips.
- Like, dislike, or block a track or artist directly from the player.
- Save liked Flow tracks to the library and optionally download them.
- Review the last 500 played tracks and see which ones came from the library.

See [Harmony Flow architecture](docs/HARMONY_FLOW.md) for the current behavior and design limits.

## Existing Harmony Music Features

- YouTube and YouTube Music playback without an account
- Queue, radio, playlists, favorites, albums, and artists
- Playback cache and song downloads
- Streaming quality controls and silence skipping
- Synced and plain lyrics
- Android Auto, sleep timer, and equalizer support
- Android, Windows, and Linux targets
- Piped playlist integration

## Development

### Requirements

- Flutter 3.24.2 or a compatible stable Flutter release
- Dart SDK supplied by Flutter
- Visual Studio with **Desktop development with C++** for Windows builds
- Android Studio and an Android SDK for Android builds

### Run Locally

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Build a Windows release:

```bash
flutter build windows --release
```

Build an Android APK:

```bash
flutter build apk --release
```

No Last.fm key is required. When configured in Settings, a Last.fm API key is stored locally and is used only to discover similar artist/title pairs; playback still resolves through the app's existing music provider.

## Project Status

This repository currently publishes source code only. The manual Windows workflow creates an unsigned portable build for testing.

## Privacy

Listening history used by Flow, blocked tracks, and recommendation data stay on the device. Flow does not require an account or a separate recommendation server. The app still contacts music providers for metadata, streams, artwork, lyrics, and optional Last.fm recommendations.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Changes should preserve upstream attribution and include focused tests for recommendation or queue logic.

## License And Upstream Terms

This fork preserves the upstream history and [GPL-3.0 license](LICENSE). The upstream README also states these additional conditions:

- Copied or modified versions cannot be used for non-free or profit purposes.
- Copied or modified versions cannot be published to closed-source app repositories such as Play Store or App Store.

Those additional statements may not be standard GPL terms. This repository preserves them as upstream project conditions and does not provide legal advice. Review the complete license and upstream project terms before redistribution.

## Disclaimer

This software is provided as-is, without warranty. It is not sponsored, funded, authorized, or endorsed by any content provider. Songs, artwork, names, and trademarks belong to their respective owners. Users and distributors are responsible for complying with provider terms, copyright law, and local law.

## Credits

- [Bikram-Kumar/Harmony-Music](https://github.com/Bikram-Kumar/Harmony-Music)
- [anandnet/Harmony-Music](https://github.com/anandnet/Harmony-Music)
- [Flutter](https://docs.flutter.dev/)
- [ytmusicapi](https://github.com/sigma67/ytmusicapi) as an upstream learning reference
- [LRCLIB](https://lrclib.net/) for lyrics
- [Piped](https://piped.video/) for playlist integration
