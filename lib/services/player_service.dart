import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';

enum PlayerPlaybackState { idle, loading, playing, paused, completed, error }

class PlayerService {
  static final PlayerService _instance = PlayerService._internal();
  factory PlayerService() => _instance;

  final AudioPlayer _audioPlayer = AudioPlayer();
  final ValueNotifier<PlayerPlaybackState> playbackStateNotifier =
      ValueNotifier(PlayerPlaybackState.idle);

  StreamSubscription<PlayerState>? _stateSubscription;
  Song? _currentSong;

  PlayerService._internal() {
    _stateSubscription = _audioPlayer.playerStateStream.listen(
      _onPlayerStateChanged,
      onError: (error, stackTrace) {
        playbackStateNotifier.value = PlayerPlaybackState.error;
      },
    );
  }

  Song? get currentSong => _currentSong;

  bool get hasSource => _audioPlayer.audioSource != null;

  bool get isPlaying => _audioPlayer.playing;

  void _onPlayerStateChanged(PlayerState state) {
    switch (state.processingState) {
      case ProcessingState.idle:
        playbackStateNotifier.value = PlayerPlaybackState.idle;
        break;
      case ProcessingState.loading:
      case ProcessingState.buffering:
        playbackStateNotifier.value = PlayerPlaybackState.loading;
        break;
      case ProcessingState.ready:
        playbackStateNotifier.value =
            state.playing
                ? PlayerPlaybackState.playing
                : PlayerPlaybackState.paused;
        break;
      case ProcessingState.completed:
        playbackStateNotifier.value = PlayerPlaybackState.completed;
        break;
    }
  }

  Map<String, String>? _normalizeHeaders(Map<String, dynamic>? rawHeaders) {
    if (rawHeaders == null || rawHeaders.isEmpty) {
      return null;
    }

    final headers = <String, String>{};
    rawHeaders.forEach((key, value) {
      final k = key.toString().trim();
      final v = value.toString().trim();
      if (k.isNotEmpty && v.isNotEmpty) {
        headers[k] = v;
      }
    });

    return headers.isEmpty ? null : headers;
  }

  Future<void> playStream({
    required Song song,
    required String audioUrl,
    Map<String, dynamic>? headers,
  }) async {
    final trimmedUrl = audioUrl.trim();
    if (trimmedUrl.isEmpty) {
      throw StateError('audioUrl cannot be empty');
    }

    _currentSong = song;
    playbackStateNotifier.value = PlayerPlaybackState.loading;

    final source = AudioSource.uri(
      Uri.parse(trimmedUrl),
      headers: _normalizeHeaders(headers),
    );

    await _audioPlayer.stop();
    await _audioPlayer.setAudioSource(source);
    await _audioPlayer.play();
  }

  Future<void> play() async {
    if (_audioPlayer.audioSource == null) {
      return;
    }
    await _audioPlayer.play();
  }

  Future<void> pause() async {
    await _audioPlayer.pause();
  }

  Future<void> stop() async {
    await _audioPlayer.stop();
    playbackStateNotifier.value = PlayerPlaybackState.idle;
  }

  Future<void> disposePlayer() async {
    await _stateSubscription?.cancel();
    await _audioPlayer.dispose();
    playbackStateNotifier.dispose();
  }
}
