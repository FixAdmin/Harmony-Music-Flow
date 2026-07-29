# Harmony Flow Architecture

Harmony Flow is a local-first adaptive queue layered on top of Harmony Music's existing playback and music-provider services. It does not run a separate recommendation server and does not require a user account.

## Data Flow

1. Playback events record starts, meaningful completion, early skips, likes, dislikes, and recent activity.
2. The taste profile aggregates artist and track affinity while applying recency and negative-feedback penalties.
3. Candidate providers collect related tracks from YouTube Music radio/related responses, local favorites, downloads, recent tracks, and optional Last.fm similar-track metadata.
4. Identity normalization removes duplicate tracks and weak artist/title matches.
5. The ranker scores affinity, completion, novelty, source confidence, station fit, repetition, blacklist state, and recent exposure.
6. The queue planner mixes library and discovery candidates, limits artist streaks, preserves a playable look-ahead, and replenishes before the queue is exhausted.
7. Decisions and actual playback are retained locally for debugging and quality review.

## Flow Modes And Stations

The default Flow uses the broad taste profile. Generated stations use current profile clusters and available candidate metadata to express narrower directions. They are not a hardcoded global genre catalog: the visible set can change as the profile and available recommendations change.

Changing a station starts its queue immediately. Station context affects candidate collection and ranking, while the same playback safeguards and feedback system remain active.

## Feedback

- A like strengthens track and artist affinity and can trigger the existing library/download automation.
- An early skip contributes a negative signal only after playback is valid; stream failures and very short startup attempts are filtered.
- Dislike/blacklist actions immediately exclude matching tracks, and artist blocks exclude that artist from future Flow queues.
- Recently played tracks and repeated artists receive penalties to reduce loops.

## Cold Start And Failure Behavior

With little history, Flow starts from the current or recent track, local favorites, downloads, and provider radio results. If a provider fails, cached/local candidates remain usable. Last.fm is optional and is never the playback source; returned artist/title pairs must resolve through the existing music provider.

The queue keeps a look-ahead buffer and guards natural completion separately from manual playback requests. This prevents the completed track from briefly restarting while the next stream is being resolved.

## Local Storage

Hive boxes store listening events, taste profiles, recommendation caches, Flow sessions, queue plans, feedback, blacklists, and playback audit entries. Settings can clear recommendation and Flow data. No new cloud synchronization or account backend is included in this version.

## Current Limits

- Recommendation quality depends on provider metadata and a growing local history.
- No collaborative filtering across users is performed.
- Generated stations can converge when candidate pools are small or metadata is sparse.
- Last.fm improves discovery breadth but requires a user-supplied API key.
- Mobile/desktop library synchronization is not implemented in the current public scope.

