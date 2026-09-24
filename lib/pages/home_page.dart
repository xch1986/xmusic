import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player_controller.dart';
import '../settings.dart';
import '../subsonic.dart';
import '../widgets.dart';
import 'mini_player.dart';
import 'player_page.dart';
import 'search_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.settings, required this.controller});

  final AppSettings settings;
  final PlayerController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Map<String, dynamic>>> _toplists;
  late Future<List<Song>> _daily30;
  late Future<List<Song>> _localRec;
  late Future<List<Map<String, dynamic>>> _qqPlaylists;

  SubsonicClient get _client => widget.controller.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final ext = widget.controller.external;
    // 真实排行榜：网易云 + （有QQ cookie时）QQ 榜单
    _toplists = _loadToplists();
    // 每日30首：飙升榜/新歌榜/原创榜 各取前10去重（避开热歌榜，避免与下方排行榜网格重复）
    _daily30 = _loadDaily30();
    // QQ 精选歌单（硬编码 dissid，本地列表零网络请求；点进去才拉歌曲）
    _qqPlaylists = ext.qqPlaylists();
    // 本地推荐
    _localRec = _client.randomSongs(size: 20);
  }

  /// 排行榜：网易云榜单 + QQ 热榜/新歌榜/飙升榜/流行指数榜混排（网易云前8 + QQ前4）。
  /// [xmusic] 2026-09-24 修复：QQ 榜单数据接口匿名可用（fcg_v8_toplist_cp），
  /// 不再依赖 QQ cookie 才显示——车机/未填 cookie 也能看到 QQ 四大榜；
  /// 有 cookie 时点进榜单走 QQ 音源播放，无 cookie 时由播放链网易云/酷我兜底。
  Future<List<Map<String, dynamic>>> _loadToplists() async {
    final ext = widget.controller.external;
    var lists = await ext
        .getToplists()
        .timeout(const Duration(seconds: 15))
        .catchError((_) => <Map<String, dynamic>>[]);
    final qq = await ext
        .qqToplists()
        .timeout(const Duration(seconds: 15))
        .catchError((_) => <Map<String, dynamic>>[]);
    if (qq.isNotEmpty) {
      lists = [...lists, ...qq.map((m) => {...m, 'source': 'qq'})];
    }
    return lists;
  }

  /// 每日30首：设置了 QQ cookie 用 QQ 热歌榜（播放走 QQ）；否则酷狗TOP500 → 网易云匹配播放。
  Future<List<Song>> _loadDaily30() async {
    final ext = widget.controller.external;
    final cookie = widget.settings.qqCookie;
    if (cookie.trim().isNotEmpty) {
      final qq = await ext.daily30FromQq(cookie: cookie);
      if (qq.isNotEmpty) return qq;
    }
    return ext.daily30FromKugou();
  }

  Future<void> _reload() async {
    _load();
    await Future.wait([_toplists, _daily30, _qqPlaylists]);
  }

  Future<void> _playSongs(List<Song> songs, int index) async {
    await widget.controller.playQueue(songs, index);
    if (mounted) setState(() {});
    if (context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerPage(
          settings: widget.settings,
          controller: widget.controller,
        ),
      ));
    }
  }

  Future<void> _openPlaylist(String name, String playlistId,
      {String? coverUrl, List<Song>? songs}) async {
    // 已有数据（如热歌榜大卡片首页已加载）：直接进详情页，秒开不转圈、不再二次请求
    if (songs != null) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _PlaylistDetail(
          title: name,
          songs: songs,
          client: _client,
          settings: widget.settings,
          controller: widget.controller,
          coverUrl: coverUrl,
          onPlay: (i) => _playSongs(songs, i),
        ),
      ));
      return;
    }
    final ext = widget.controller.external;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    List<Song> fetched;
    String? error;
    try {
      fetched = await ext.getPlaylistSongs(playlistId).timeout(const Duration(seconds: 20));
    } catch (e) {
      fetched = const [];
      error = '加载失败（$e）';
    }
    if (fetched.isEmpty && error == null) error = '没有歌曲数据';
    if (!mounted) return;
    Navigator.pop(context); // dismiss loading
    // 无论成败都进入详情页：失败显示原因+重试，绝不空白页或无声返回
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PlaylistDetail(
        title: name,
        songs: fetched,
        client: _client,
        settings: widget.settings,
        controller: widget.controller,
        coverUrl: coverUrl,
        error: error,
        onRetry: () => _openPlaylist(name, playlistId, coverUrl: coverUrl),
        onPlay: (i) => _playSongs(fetched, i),
      ),
    ));
  }

  /// QQ 榜单详情：拉 QQ 榜单歌曲（songmid），进列表页，播放走 QQ（带 cookie）。
  Future<void> _openQqToplist(String name, String id, String? coverUrl) async {
    final ext = widget.controller.external;
    final cookie = widget.settings.qqCookie;
    final songs = await ext.qqToplistSongs(id, cookie: cookie, limit: 50);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PlaylistDetail(
        title: name,
        songs: songs,
        client: _client,
        settings: widget.settings,
        controller: widget.controller,
        coverUrl: coverUrl,
        onPlay: (i) => _playSongs(songs, i),
      ),
    ));
  }

  /// QQ 精选歌单详情：qzone 老接口拉歌曲（songmid），进列表页，播放走 QQ→网易云/酷我兜底。
  Future<void> _openQqPlaylist(String name, String dissid) async {
    final ext = widget.controller.external;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    List<Song> songs;
    String? error;
    try {
      songs = await ext.qqPlaylistSongs(dissid, limit: 100).timeout(const Duration(seconds: 20));
    } catch (e) {
      songs = const [];
      error = '加载失败（$e）';
    }
    if (songs.isEmpty && error == null) error = '没有歌曲数据';
    if (!mounted) return;
    Navigator.pop(context);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PlaylistDetail(
        title: name,
        songs: songs,
        client: _client,
        settings: widget.settings,
        controller: widget.controller,
        error: error,
        onRetry: () => _openQqPlaylist(name, dissid),
        onPlay: (i) => _playSongs(songs, i),
      ),
    ));
  }

  /// 本地推荐：点歌单卡先进歌单列表页（不再点卡片直接播单曲）
  Future<void> _openLocalRec(List<Song> songs) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PlaylistDetail(
        title: '本地推荐',
        songs: songs,
        client: _client,
        settings: widget.settings,
        controller: widget.controller,
        onPlay: (i) => _playSongs(songs, i),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('音素'),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SearchPage(settings: widget.settings, controller: widget.controller),
            )),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            // 每日30首大卡片
            FutureBuilder<List<Song>>(
              future: _daily30,
              builder: (context, snap) {
                if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
                return _dailyCard(snap.data!);
              },
            ),
            // 排行榜网格
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('排行榜',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700)),
            ),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _toplists,
              builder: (context, snap) {
                if (!snap.hasData || snap.data!.isEmpty) {
                  return const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('加载排行榜...')));
                }
                // 网易云前8 + QQ前4
                final ne = snap.data!.where((t) => t['source'] != 'qq').take(8).toList();
                final qq = snap.data!.where((t) => t['source'] == 'qq').take(4).toList();
                final lists = [...ne, ...qq];
                // [xmusic] 2026-09-24 车机横屏参考网易云车机版：一行6个、方形封面+下方标题，
                // 卡片更小不占满整屏；手机仍 3 列。
                final car = isCarScreen(context);
                return GridView.count(
                  crossAxisCount: car ? 6 : 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  mainAxisSpacing: car ? 12 : 10,
                  crossAxisSpacing: car ? 10 : 10,
                  childAspectRatio: car ? 0.92 : 1.1,
                  children: lists.map((t) => _toplistCard(
                    t['name'] as String,
                    t['id'] as String,
                    t['coverImgUrl'] as String?,
                    source: (t['source'] ?? '') as String,
                  )).toList(),
                );
              },
            ),
            // QQ 精选歌单（用户强烈要求；硬编码 dissid，点进才拉歌曲）
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('QQ歌单',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    tooltip: '换一批',
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    onPressed: () {
                      setState(() => _qqPlaylists = widget.controller.external.qqPlaylists());
                    },
                  ),
                ],
              ),
            ),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _qqPlaylists,
              builder: (context, snap) {
                final list = snap.data ?? const [];
                return GridView.count(
                  crossAxisCount: isCarScreen(context) ? 6 : 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  mainAxisSpacing: isCarScreen(context) ? 12 : 10,
                  crossAxisSpacing: isCarScreen(context) ? 10 : 10,
                  childAspectRatio: isCarScreen(context) ? 1.0 : 1.05,
                  children: list.map((p) => _qqPlaylistCard(
                    p['name'] as String,
                    p['dissid'] as String,
                    p['coverImgUrl'] as String?,
                  )).toList(),
                );
              },
            ),
            // 本地推荐歌单卡（点击进歌单列表页，不是单曲卡）
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text('歌单推荐',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FutureBuilder<List<Song>>(
                future: _localRec,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return _miniCard(
                      title: '本地推荐',
                      subtitle: '加载失败·重试',
                      icon: Icons.queue_music_rounded,
                      colors: const [Color(0xFF00A884), Color(0xFF2FB8A0)],
                      onTap: () => setState(_load),
                    );
                  }
                  if (!snap.hasData || snap.data!.isEmpty) {
                    return _miniCard(
                      title: '本地推荐',
                      subtitle: '加载中...',
                      icon: Icons.queue_music_rounded,
                      colors: const [Color(0xFF00A884), Color(0xFF2FB8A0)],
                      onTap: null,
                    );
                  }
                  final songs = snap.data!;
                  return _miniCard(
                    title: '本地推荐',
                    subtitle: '${songs.length > 12 ? 12 : songs.length}首 · 随机推荐',
                    icon: Icons.queue_music_rounded,
                    colors: const [Color(0xFF00A884), Color(0xFF2FB8A0)],
                    onTap: () => _openLocalRec(songs),
                  );
                },
              ),
            ),
          ],
          ),
      ),
    );
  }

  Widget _dailyCard(List<Song> songs) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        elevation: 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openPlaylist('每日30首', '', songs: songs),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFFE85D4A), Color(0xFFF08A3E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 36),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('每日30首', style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('${songs.length}首 · 飙升/新歌/原创推荐', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70)),
                    ],
                  ),
                ),
                const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 半宽歌单卡（本地推荐）：渐变底 + 图标 + 标题 + 副标题，点击进歌单页。
  Widget _miniCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> colors,
    VoidCallback? onTap,
  }) {
    return Material(
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 110,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: Colors.white, size: 30),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toplistCard(String name, String id, String? coverUrl,
      {String source = ''}) {
    // [xmusic] 车机横屏参考网易云车机版：方封面 + 下方标题；手机保持原铺满卡。
    if (isCarScreen(context)) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => source == 'qq'
            ? _openQqToplist(name, id, coverUrl)
            : _openPlaylist(name, id, coverUrl: coverUrl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: (coverUrl != null && coverUrl.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        httpHeaders: const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://music.163.com/'},
                        placeholder: (_, __) => Container(color: const Color(0xFF262626)),
                        errorWidget: (_, __, ___) => Container(color: const Color(0xFF262626)),
                      )
                    : Container(
                        color: const Color(0xFF262626),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(8),
                        child: Text(name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }
    final theme = Theme.of(context);
    return Material(
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => source == 'qq'
            ? _openQqToplist(name, id, coverUrl)
            : _openPlaylist(name, id, coverUrl: coverUrl),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (coverUrl != null && coverUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: coverUrl,
                  fit: BoxFit.cover,
                  httpHeaders: const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://music.163.com/'},
                  placeholder: (_, __) => Container(color: theme.colorScheme.surfaceContainerHighest),
                  errorWidget: (_, __, ___) => Container(color: theme.colorScheme.surfaceContainerHighest),
                )
              else
                // QQ 榜单等无封面：渐变底 + 榜单名文字，不再只显示灰块
                Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              if (coverUrl != null && coverUrl.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  /// QQ 精选歌单卡（网易云车机版风格：方形圆角封面 + 下方标题，无封面图用深灰渐变+图标）。
  Widget _qqPlaylistCard(String name, String dissid, String? coverUrl) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openQqPlaylist(name, dissid),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  (coverUrl != null && coverUrl.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: coverUrl,
                          fit: BoxFit.cover,
                          httpHeaders: const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://y.qq.com/'},
                          placeholder: (_, __) => Container(color: theme.colorScheme.surfaceContainerHighest),
                          errorWidget: (_, __, ___) => Container(color: theme.colorScheme.surfaceContainerHighest),
                        )
                      : Container(color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(Icons.queue_music_rounded, color: theme.colorScheme.onSurfaceVariant)),
                  // 底部暗渐变，压白字
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x99000000)],
                        stops: [0.55, 1.0],
                      ),
                    ),
                    child: SizedBox.expand(),
                  ),
                  Positioned(
                    left: 10, right: 34, bottom: 10,
                    child: Text(name,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, height: 1.2)),
                  ),
                  Positioned(
                    right: 8, bottom: 8,
                    child: Container(
                      width: 28, height: 28,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
Widget build(BuildContext context) {
    final title = widget.title;
    final songs = widget.songs;
    final client = widget.client;
    final settings = widget.settings;
    final controller = widget.controller;
    final onPlay = widget.onPlay;
    final coverUrl = widget.coverUrl;
    final error = widget.error;
    final onRetry = widget.onRetry;
    return Scaffold(
      // 不透明背景：避免半透明主题透出下层页面导致列表区域视觉混乱（0.2.x 修复回归）
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Expanded(
            child: Column(
              children: [
                if (coverUrl != null && coverUrl!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: coverUrl!,
                      width: 80, height: 80, fit: BoxFit.cover,
                      httpHeaders: const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://music.163.com/'},
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('共 ${_visibleIndices.length} 首', style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _visibleIndices.isEmpty || error != null ? null : () => onPlay(0),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('播放全部'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _visibleIndices.isEmpty || error != null ? null : () {
                    songs.shuffle();
                    onPlay(0);
                  },
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('随机'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_rounded, size: 40),
                      const SizedBox(height: 8),
                      Text(error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      if (onRetry != null)
                        FilledButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('重试'),
                        ),
                    ],
                  ),
                )
              : _visibleIndices.isEmpty
                ? const Center(child: Text('已全部移除'))
                : ListView.builder(
                    itemCount: _visibleIndices.length,
                    itemBuilder: (context, k) {
                      final i = _visibleIndices[k];
                      final song = songs[i];
                      return Dismissible(
                        key: ValueKey('pl_${title}_${song.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Theme.of(context).colorScheme.error,
                          child: const Icon(Icons.delete_outline_rounded,
                              color: Colors.white),
                        ),
                        onDismissed: (_) => _removeSong(song),
                        child: SongTile(
                          song: song,
                          client: client,
                          onTap: () => onPlay(i),
                        ),
                      );
                    },
                  ),
              ),
            ],
          ),
        ),
        // 迷你播放条放 body 底部而不是 bottomNavigationBar：
        // 避免个别设备上 bottomNavigationBar 槽位把迷你条撑满全屏、挤没列表（0.2.x 修复回归）
        MiniPlayer(settings: settings, controller: controller),
      ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.song, required this.client, required this.onTap});
  final Song song;
  final SubsonicClient client;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 130,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(children: [
              CoverImage(client: client, coverId: song.coverArt, coverUrl: song.coverUrl, size: 130, radius: 12, requestSize: 360),
              Positioned(right: 4, bottom: 4, child: Icon(Icons.play_circle_fill_rounded, size: 28, color: Colors.white.withOpacity(0.9))),
            ]),
            const SizedBox(height: 6),
            Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
            Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
