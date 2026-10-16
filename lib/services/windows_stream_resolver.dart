import 'dart:async';
import 'dart:convert';
import 'dart:io';

class WindowsStreamResolver {
  static Future<List<Map<String, dynamic>>> fetch(String videoId) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
      throw const FormatException('Invalid video ID');
    }
    final tools = Directory(Platform.environment['HARMONY_NETWORK_TOOLS'] ??
        '${File(Platform.resolvedExecutable).parent.path}/network_tools');
    final extractor = File('${tools.path}/yt-dlp.exe');
    final runtime = File('${tools.path}/node.exe');
    if (!await extractor.exists() || !await runtime.exists()) {
      throw const FileSystemException('Bundled stream resolver is missing');
    }
    final process = await Process.start(extractor.path, [
      '--ignore-config',
      '--no-update',
      '--no-playlist',
      '--no-warnings',
      '--no-remote-components',
      '--js-runtimes',
      'node:${runtime.path}',
      '--extractor-args',
      'youtube:player_client=web_embedded',
      '--socket-timeout',
      '15',
      '--retries',
      '1',
      '--extractor-retries',
      '1',
      '--dump-single-json',
      '--skip-download',
      'https://www.youtube.com/watch?v=$videoId',
    ]);
    try {
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.drain<void>();
      final results = await Future.wait<Object?>([
        output,
        errors,
        process.exitCode,
      ]).timeout(const Duration(seconds: 60));
      if (results[2] != 0) {
        // Extractor diagnostics can include signed URLs and session tokens.
        throw const HttpException('Unable to resolve YouTube audio');
      }
      return parseFormats(jsonDecode(results[0] as String) as Map);
    } on TimeoutException {
      process.kill();
      await process.exitCode;
      rethrow;
    }
  }

  static List<Map<String, dynamic>> parseFormats(Map data) {
    final formats = data['formats'] as List? ?? const [];
    final duration = ((data['duration'] as num? ?? 0) * 1000).round();
    final result = <Map<String, dynamic>>[];
    for (final raw in formats.whereType<Map>()) {
      final codec = raw['acodec'] as String? ?? 'none';
      final itag = int.tryParse(raw['format_id']?.toString() ?? '');
      final uri = Uri.tryParse(raw['url'] as String? ?? '');
      if (raw['vcodec'] != 'none' ||
          codec == 'none' ||
          itag == null ||
          uri == null ||
          uri.scheme != 'https' ||
          !uri.host.endsWith('.googlevideo.com')) continue;
      final headers = <String, String>{};
      final sourceHeaders = raw['http_headers'] ?? data['http_headers'];
      if (sourceHeaders is Map) {
        for (final entry in sourceHeaders.entries) {
          if (entry.key is String && entry.value is String) {
            headers[entry.key as String] = entry.value as String;
          }
        }
      }
      result.add({
        'itag': itag,
        'audioCodec': codec.contains('mp4a') ? 'Codec.mp4a' : 'Codec.opus',
        'bitrate': (((raw['abr'] ?? raw['tbr'] ?? 0) as num) * 1000).round(),
        'approxDurationMs': duration,
        'loudnessDb': (data['loudness'] as num?)?.toDouble() ?? 0.0,
        'size':
            ((raw['filesize'] ?? raw['filesize_approx'] ?? 0) as num).toInt(),
        'url': uri.toString(),
        'headers': headers,
      });
    }
    if (result.isEmpty) {
      throw const FormatException('No available audio streams');
    }
    return result;
  }
}
