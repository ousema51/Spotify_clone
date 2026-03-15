import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class PlayerService {
  static final PlayerService _instance = PlayerService._internal();
  factory PlayerService() => _instance;

  final AudioPlayer player = AudioPlayer();

  PlayerService._internal();

  Future<bool> playUrl(String url) async {
    try {
      print('[PlayerService] playUrl: $url');
      await player.setUrl(url);
      await player.play();
      return true;
    } catch (e, st) {
      print('[PlayerService] playUrl error: $e');
      print(st);
      return false;
    }
  }

  Future<bool> playYoutubeVideo(String videoId) async {
    if (kIsWeb) {
      print('[PlayerService] playYoutubeVideo: not supported on Web (CORS)');
      return false;
    }
    try {
      print('[PlayerService] playYoutubeVideo attempt for: $videoId');
      // Normalize videoId: accept full URL or bare id
      String id = videoId;
      try {
        if (videoId.contains('watch?v=')) {
          final uri = Uri.parse(videoId);
          id = uri.queryParameters['v'] ?? videoId;
        }
      } catch (_) {}

      final yt = YoutubeExplode();
      try {
        print('[PlayerService] resolving manifest for id: $id');
        final manifest = await yt.videos.streamsClient.getManifest(id);
        final audio = manifest.audioOnly.withHighestBitrate();
        final url = audio.url.toString();
        print('[PlayerService] resolved audio url: $url');
        final ok = await playUrl(url);
        print('[PlayerService] playUrl returned: $ok');
        return ok;
      } finally {
        yt.close();
      }
    } catch (e, st) {
      print('[PlayerService] playYoutubeVideo error: $e');
      print(st);
      return false;
    }
  }

  Future<void> pause() async {
    await player.pause();
  }

  Future<void> resume() async {
    await player.play();
  }

  Future<void> stop() async {
    await player.stop();
  }

  Stream<bool> get playingStream => player.playerStateStream.map((s) => s.playing);
  Stream<PlayerState> get playerStateStream => player.playerStateStream;
  Stream<Duration> get positionStream => player.positionStream;
}