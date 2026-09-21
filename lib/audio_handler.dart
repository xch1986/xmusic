import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// AudioService handler：把 just_audio 的播放状态桥接到系统通知栏/锁屏/车机。
class MyAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  /// 由 PlayerController 设置：通知栏点 next/prev 时回调。
  Future<void> Function()? onSkipNext;
  Future<void> Function()? onSkipPrevious;

  MyAudioHandler() {
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    _player.durationStream.listen((d) {
      final mi = mediaItem.value;
      if (d != null && mi != null) {
        mediaItem.add(mi.copyWith(duration: d));
      }
    });
  }

  AudioPlayer get player => _player;

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    await onSkipNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    await onSkipPrevious?.call();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> onStart(mediaId) async {
    // 从通知栏恢复时不要自动播放，等用户主动点
    await _player.stop();
  }

  void setMediaItem(MediaItem item) {
    mediaItem.add(item);
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }
}
