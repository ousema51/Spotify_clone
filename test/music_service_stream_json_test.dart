import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/services/music_service.dart';

void main() {
  group('MusicService stream JSON normalization', () {
    test('keeps canonical backend payload intact', () {
      final input = {
        'success': true,
        'data': {
          'audio_url': 'https://audio.example.com/track.m4a',
          'headers': {'Referer': 'https://music.youtube.com/'},
          'video_id': 'dQw4w9WgXcQ',
          'title': 'Track',
          'duration': 215,
          'source': 'yt-dlp',
        },
      };

      final result = MusicService.normalizeStreamResultForTesting(input);

      expect(result['success'], true);
      final data = result['data'] as Map<String, dynamic>;
      expect(data['audio_url'], 'https://audio.example.com/track.m4a');
      expect(data['headers']['Referer'], 'https://music.youtube.com/');
      expect(data['video_id'], 'dQw4w9WgXcQ');
      expect(data['duration'], 215);
      expect(data['source'], 'yt-dlp');
    });

    test('accepts legacy keys and coerces header values', () {
      final input = {
        'success': true,
        'data': {
          'url': 'https://audio.example.com/legacy.webm',
          'headers': {'X-Num': 42},
          'duration': '189.9',
        },
      };

      final result = MusicService.normalizeStreamResultForTesting(
        input,
        fallbackVideoId: 'fallback12345',
        fallbackTitle: 'Fallback Song',
      );

      expect(result['success'], true);
      final data = result['data'] as Map<String, dynamic>;
      expect(data['audio_url'], 'https://audio.example.com/legacy.webm');
      expect(data['headers']['X-Num'], '42');
      expect(data['video_id'], 'fallback12345');
      expect(data['title'], 'Fallback Song');
      expect(data['duration'], 189);
    });

    test('fails when no usable audio url exists', () {
      final input = {
        'success': true,
        'data': {
          'headers': {'A': 'B'},
        },
      };

      final result = MusicService.normalizeStreamResultForTesting(input);

      expect(result['success'], false);
      expect(result['message'], contains('audio_url'));
    });
  });
}
