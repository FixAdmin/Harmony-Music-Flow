# Contributing

Thanks for helping improve Harmony Music Flow. Small, testable changes are preferred.

## Before Opening A Pull Request

1. Create a branch from the repository's current default branch.
2. Keep changes focused and preserve attribution to both upstream Harmony Music projects.
3. Do not commit API keys, tokens, signing keys, personal listening data, Hive databases, build output, or local paths.
4. Add or update tests for ranking, queue planning, feedback, persistence, or playback lifecycle changes.
5. Run the checks below.

```bash
flutter pub get
flutter analyze
flutter test
```

For player or queue changes, also run the app and verify first playback, next/previous controls, natural track completion, manual skipping, Flow switching, and poor-network transitions.

## Recommendation Changes

Explain which signal or candidate source changed and how the change avoids repetition, feedback loops, and overfitting to recent playback. Deterministic unit tests are expected for scoring and queue policy changes.

## Translations

Do not force the application locale. Existing language selection must continue to work, and missing custom translations must fall back to English.

## Legal And Content Boundaries

Do not add bundled copyrighted media, credentials, provider circumvention instructions, or branding that implies endorsement by an upstream maintainer or content provider. Contributions remain subject to the repository license and preserved upstream conditions.
