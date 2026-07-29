# Harmony Music Flow

A community-maintained fork of [Bikram-Kumar/Harmony-Music](https://github.com/Bikram-Kumar/Harmony-Music), which continues the original [anandnet/Harmony-Music](https://github.com/anandnet/Harmony-Music) project.

Harmony Music is a Flutter music client for Android, Windows, and Linux. This fork adds a local-first recommendation system and **Harmony Flow**, an adaptive queue that mixes library tracks with related discoveries.

> This fork is unofficial and is not affiliated with or endorsed by the upstream maintainers, YouTube, YouTube Music, Last.fm, or any content provider. Recommendation behavior may change as playback data is evaluated.

![Harmony Music cover](cover.png)

## What This Fork Adds

- **Harmony Flow**: a continuously replenished smart queue that starts playing immediately.
- **Adaptive stations**: generated directions based on the current taste profile instead of a fixed genre list.
- **Local taste profile**: learns from plays, completion, likes, early skips, recency, and repeated artists.
- **Mixed candidate sources**: YouTube Music radio and related tracks, the local library, downloads, favorites, and an optional Last.fm fallback.
- **Flow feedback**: dislike tracks, blacklist tracks or artists, and remove blacklist entries in Settings.
- **Playback audit**: inspect up to 500 recently played tracks with library/source markers.
- **Library automation**: liked Flow tracks can be added to the library and downloaded when the existing download support is available.
- **English fallback**: existing language selection is preserved; custom strings without a translation remain in English.

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

This repository currently publishes source code only. GitHub Actions can create an **unsigned** portable Windows artifact for testing. No official binaries, signing identity, support channel, or release schedule are promised yet.

## Privacy

Harmony Flow stores listening events, taste data, queue decisions, blacklist entries, and recommendation caches locally in Hive. It does not add an account system or cloud synchronization. Network requests still occur for music metadata, streams, artwork, lyrics, and optional Last.fm recommendations.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Changes should preserve upstream attribution, local-first behavior, and focused tests for recommendation or queue logic.

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
