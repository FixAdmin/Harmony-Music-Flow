import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/stream_service.dart';
import 'package:harmonymusic/services/windows_stream_resolver.dart';

void main() {
  Map<String, dynamic> format(
          {String url = 'https://rr1.googlevideo.com/audio',
          String vcodec = 'none',
          String acodec = 'opus',
          String id = '251'}) =>
      {
        'url': url,
        'vcodec': vcodec,
        'acodec': acodec,
        'format_id': id,
        'abr': 128.5,
        'filesize': 5000000,
      };

  test('parses audio metadata and preserves headers across cache serialization',
      () {
    final formats = WindowsStreamResolver.parseFormats({
      'duration': 180.25,
      'loudness': -6,
      'http_headers': {'User-Agent': 'test-player'},
      'formats': [format()],
    });
    final audio = Audio.fromJson(formats.single);
    expect(audio.duration, 180250);
    expect(audio.size, 5000000);
    expect(audio.audioCodec, Codec.opus);
    expect(audio.headers, {'User-Agent': 'test-player'});
    expect(Audio.fromJson(audio.toJson()).headers, audio.headers);
  });

  test('ignores video, non-media hosts, unencrypted URLs, and missing codecs',
      () {
    final formats = WindowsStreamResolver.parseFormats({
      'formats': [
        format(),
        format(vcodec: 'avc1'),
        format(acodec: 'none'),
        format(url: 'file:///song'),
        format(url: 'http://rr1.googlevideo.com/a'),
        format(url: 'https://googlevideo.com.attacker.example/a'),
        format(id: 'sb0'),
      ]
    });
    expect(formats, hasLength(1));
  });

  test('rejects responses without playable audio', () {
    expect(() => WindowsStreamResolver.parseFormats({'formats': []}),
        throwsFormatException);
  });

  test('legacy downloaded audio does not require new headers', () {
    final audio = Audio.fromJson({
      'itag': 140,
      'audioCodec': 'Codec.mp4a',
      'url': 'file:///saved-track.m4a'
    });
    expect(audio.headers, isNull);
    expect(audio.audioCodec, Codec.mp4a);
  });

  test('invalid IDs never invoke an external process', () async {
    await expectLater(
        WindowsStreamResolver.fetch('--bad-id'), throwsFormatException);
  });
}
