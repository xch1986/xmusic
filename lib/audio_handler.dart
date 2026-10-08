import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// 全局共享均衡器：AndroidEqualizer 经 AudioPipeline 挂在共享 player 上，
/// 播放页/设置页直接调 applyEqualizer 应用预设或自定义增益。
final AndroidEqualizer sharedEqualizer = AndroidEqualizer();
final AudioPlayer sharedPlayer = AudioPlayer(
  audioPipeline: AudioPipeline(androidAudioEffects: [sharedEqualizer]),
);

/// EQ 预设 → 5 段参考增益（低→高）。AndroidEqualizer 频段数由设备决定，
/// 多于 5 段时循环复用，少于 5 段取前 N。
const Map<String, List<double>> _kEqPresets = {
  'pop': [2.5, 1.0, -0.5, 1.0, 2.0], // 流行
  'rock': [3.0, 1.5, -1.0, 1.5, 3.0], // 摇滚
  'electronic': [2.0, 0.5, 1.5, 0.5, 2.0], // 电子
  'classical': [2.0, 1.0, 0.0, 1.0, 2.0], // 古典
  'bass': [6.0, 4.0, 1.0, -2.0, -1.0], // 低音增强
  'vocal': [-1.5, 1.5, 4.0, 1.5, -1.5], // 人声
  'stereo': [4.0, 1.0, -2.0, 1.0, 4.0], // 立体声
};

/// 应用 EQ：preset = off/pop/rock/electronic/classical/bass/vocal/custom；
/// custom 时 gains 为逗号分隔的 dB（如 "3,1,-1,1,3"）。非 Android 静默忽略。
Future<void> applyEqualizer(String preset, String gains) async {
  try {
    if (preset == 'off' || preset.isEmpty) {
      await sharedEqualizer.setEnabled(false);
      return;
    }
    await sharedEqualizer.setEnabled(true);
    final params = await sharedEqualizer.parameters;
    if (params.bands.isEmpty) return;
    List<double> src;
    if (preset == 'custom') {
      src = gains
          .split(',')
          .map((e) => double.tryParse(e.trim()) ?? 0.0)
          .toList();
    } else {
      src = _kEqPresets[preset] ?? const [];
    }
    final n = params.bands.length;
    for (var i = 0; i < n; i++) {
      final g = src.length > i ? src[i] : (src.isNotEmpty ? src.last : 0.0);
      await params.bands[i]
          .setGain(g.clamp(params.minDecibels, params.maxDecibels).toDouble());
    }
  } catch (_) {}
}

/// 全局唯一的 AudioPlayer 实例（双播问题根因修复）。
/// audio_service 在 Android 上可能因服务重建而创建第二个 MyAudioHandler 实例，
/// 若每个实例都 new 一个 AudioPlayer，会出现两首歌同时播放、进度不同的双播。
/// 所有 handler 共享同一个 player，即可杜绝该问题。

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
    // 仅拦截 AudioService 启动/恢复时的自动播放（PlayerController 接管前 allowPlay=false）。
    // PlayerController 接管后（allowPlay=true），方向盘/通知栏/蓝牙 AVRCP 的主动播放一律放行。
    if (!allowPlay) return;
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
      // 注册 play/pause/stop/skip 系统动作：车机蓝牙 AVRCP 依据 MediaSession
      // 的 PlaybackState.actions 决定方向盘按钮是否可用——缺 play/pause 时
      // 方向盘暂停/播放按钮无效（上一曲/下一曲仍可用）。
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.stop,
        MediaAction.seek,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
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
