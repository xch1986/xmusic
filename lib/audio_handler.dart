import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// 全局唯一的 AudioPlayer 实例（双播问题根因修复）。
/// audio_service 在 Android 上可能因服务重建而创建第二个 MyAudioHandler 实例，
/// 若每个实例都 new 一个 AudioPlayer，会出现两首歌同时播放、进度不同的双播。
/// 所有 handler 共享同一个 player，即可杜绝该问题。
final AudioPlayer sharedPlayer = AudioPlayer();

/// AudioService handler：把 just_audio 的播放状态桥接到系统通知栏/锁屏/车机。
class MyAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = sharedPlayer;

  /// 由 PlayerController 设置：通知栏点 next/prev 时回调。
  Future<void> Function()? onSkipNext;
  Future<void> Function()? onSkipPrevious;

  /// 阻止系统自动恢复播放（双播根因：audio_service恢复session时会自动play）
  bool allowPlay = false;

  MyAudioHandler() {
    _player.stop();
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
  Future<void> play() async {
    // 仅当 PlayerController 尚未接管时拦截（防 AudioService 启动自动恢复→双播）；
    // 一旦接管（onSkipNext 已设置），通知栏/方向盘主动播放一律放行。
    if (!allowPlay && onSkipNext == null) return;
    await _player.play();
  }

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
