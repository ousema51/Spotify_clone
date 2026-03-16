import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song.dart';

class PlayerService {
  static final PlayerService _instance = PlayerService._internal();
  factory PlayerService() => _instance;

  final AudioPlayer player = AudioPlayer();

  PlayerService._internal();

  /// Resolve a YouTube video ID into a playable audio URL
  /// using youtube_explode_dart (runs on device, not blocked)
  Future<String?> resolveStreamUrl(String videoId) async {
    final yt = YoutubeExplode();
    try {
      // Clean the video ID
      String id = videoId;
      if (videoId.contains('watch?v=')) {
        final uri = Uri.parse(videoId);
        id = uri.queryParameters['v'] ?? videoId;
      }

      print('[PlayerService] resolving stream for: $id');
      final manifest = await yt.videos.streamsClient.getManifest(id);
      final audio = manifest.audioOnly.withHighestBitrate();
      final url = audio.url.toString();
      print('[PlayerService] resolved: $url');
      return url;
    } catch (e) {
      print('[PlayerService] resolveStreamUrl error: $e');
      return null;
    } finally {
      yt.close();
    }
  }

  /// Play a direct audio URL
  Future<bool> playUrl(String url) async {
    try {
      print('[PlayerService] playUrl: ${url.substring(0, 80)}...');
      await player.setAudioSource(AudioSource.uri(Uri.parse(url)));
      await player.play();
      return true;
    } catch (e) {
      print('[PlayerService] playUrl error: $e');
      return false;
    }
  }

  /// Play a song using its streamUrl
  Future<bool> playSong(Song song) async {
    final url = song.streamUrl;
    if (url == null || url.isEmpty) return false;
    return playUrl(url);
  }

  Future<void> pause() async => await player.pause();
  Future<void> resume() async => await player.play();
  Future<void> stop() async => await player.stop();
  Future<void> seek(Duration position) async => await player.seek(position);

  Stream<bool> get playingStream =>
      player.playerStateStream.map((s) => s.playing);
  Stream<PlayerState> get playerStateStream => player.playerStateStream;
  Stream<Duration> get positionStream => player.positionStream;
  Stream<Duration?> get durationStream => player.durationStream;
}
