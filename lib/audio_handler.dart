import 'dart:async';
import 'dart:math' as math;
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// 全局唯一的 AudioPlayer 实例（双播问题根因修复）。
/// audio_service 在 Android 上可能因服务重建而创建第二个 MyAudioHandler 实例，
/// 若每个实例都 new 一个 AudioPlayer，会出现两首歌同时播放、进度不同的双播。
/// 所有 handler 共享同一个 player，即可杜绝该问题。
/// 全局均衡器（Android 系统均衡器；实际段数由设备决定）。
final AndroidEqualizer sharedEqualizer = AndroidEqualizer();

final AudioPlayer sharedPlayer = AudioPlayer(
  audioPipeline: AudioPipeline(androidAudioEffects: [sharedEqualizer]),
);

/// EQ 预设：5 个标准频点 [60, 230, 910, 3600, 14000] Hz 的增益曲线（dB）。
const Map<String, List<double>> eqPresets = {
  'flat':      [0, 0, 0, 0, 0],
  'bass':      [9, 6, 1, -1, -1],
  'vocal':     [-2, 0, 4, 4, 1],
  'stereo':    [0, 1, 1, 3, 5],
  'pop':       [-1, 2, 4, 2, -1],
  'rock':      [5, 2, -1, 2, 5],
  'classical': [3, 2, 0, 1, 3],
  'jazz':      [3, 1, 1, 2, 3],
  'electronic': [6, 4, 0, 2, 5],
};

const List<double> eqBandFreqs = [60, 230, 910, 3600, 14000];

/// 应用 EQ。preset='custom' 用 customGains（5 点 dB），否则查 [eqPresets]；
/// 'off' 直接禁用效果。按设备实际频段中心频率对数插值后 setGain。
Future<void> applyEqualizer({
  required String preset,
  List<double> customGains = const [0, 0, 0, 0, 0],
}) async {
  try {
    if (preset == 'off') {
      await sharedEqualizer.setEnabled(false);
      return;
    }
    await sharedEqualizer.setEnabled(true);
    final params = await sharedEqualizer.parameters;
    final curve = preset == 'custom'
        ? customGains
        : (eqPresets[preset] ?? eqPresets['flat']!);
    for (final band in params.bands) {
      final g = _eqGainAt(curve, band.centerFrequency);
      await band.setGain(g.clamp(params.minDecibels, params.maxDecibels));
    }
  } catch (_) {
    // 部分设备/模拟器不支持均衡器，静默失败不影响播放
  }
}

/// 在 5 个标准频点曲线上按频率对数插值取增益（dB）。
double _eqGainAt(List<double> curve, double freq) {
  const pts = eqBandFreqs;
  if (freq <= pts.first) return curve.first;
  if (freq >= pts.last) return curve.last;
  for (var i = 0; i < pts.length - 1; i++) {
    if (freq >= pts[i] && freq <= pts[i + 1]) {
      final t = (math.log(freq) - math.log(pts[i])) /
          (math.log(pts[i + 1]) - math.log(pts[i]));
      return curve[i] + (curve[i + 1] - curve[i]) * t;
    }
  }
  return 0;
}

/// AudioService handler：把 just_audio 的播放状态桥接到系统通知栏/锁屏/车机。
class MyAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = sharedPlayer;

  /// 由 PlayerController 设置：通知栏点 next/prev 时回调。
  Future<void> Function()? onSkipNext;
  Future<void> Function()? onSkipPrevious;

  /// 阻止系统自动恢复播放（双播根因：audio_service恢复session时会自动play）
  bool allowPlay = false;

  /// 进程内只有第一个实例负责清空播放状态；AudioService 后台重试成功会重建
  /// handler，若再 stop() 会把用户刚点播的歌打断（上电首曲无声的根因之一）。
  static bool _createdOnce = false;

  MyAudioHandler() {
    if (!_createdOnce) {
      _createdOnce = true;
      _player.stop();
    }
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
    // 系统自动恢复播放已由 play() 里的 allowPlay 拦截，不再无条件 stop：
    // AudioService 服务重建时同样回调 onStart，无条件 stop 会打断正在播放的歌。
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
