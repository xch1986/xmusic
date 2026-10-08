import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cover_glass.dart';
import '../external_api.dart';
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
  late Future<List<Map<String, dynamic>>> _qqPlaylists;
  late Future<List<Map<String, dynamic>>> _qqRadios;
  int _qqCategoryId = 3152; // QQ歌单分类：3152流行/41摇滚/48民谣/45电子/42说唱/61古风/49纯音乐/46爵士/43R&B/47古典
  int _qqRadioGroupIdx = 0; // QQ电台分组下拉当前选中组索引
  static const List<Map<String, dynamic>> _qqCategories = [
    {'id': 3152, 'name': '流行'},
    {'id': 41, 'name': '摇滚'},
    {'id': 48, 'name': '民谣'},
    {'id': 45, 'name': '电子'},
    {'id': 61, 'name': '古风'},
    {'id': 49, 'name': '轻音乐'},
    {'id': 46, 'name': '爵士'},
    {'id': 43, 'name': 'R&B'},
    {'id': 47, 'name': '古典'},
    {'id': 68, 'name': '中国风'},
    {'id': 59, 'name': '经典'},
    {'id': 44, 'name': '乡村'},
    {'id': 51, 'name': '蓝调'},
    {'id': 53, 'name': '新世纪'},
    {'id': 64, 'name': 'KTV热歌'},
  ];
  late Future<List<Song>> _localRec;

  SubsonicClient? get _client => widget.controller.client;

  @override
  late int _lastBlRev;

  void initState() {
    super.initState();
    _lastBlRev = widget.settings.blacklistRev;
    widget.settings.addListener(_onSettingsChanged);
    _load();
    _loadPrefs();
  }

  /// 恢复歌单广场分类 / QQ电台分组的下拉选择（用户要求下次启动记住）
  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      final cid = p.getInt('qq_category_id');
      final ridx = p.getInt('qq_radio_group_idx');
      if (!mounted) return;
      setState(() {
        _qqCategoryId = cid ?? 3152;
        _qqRadioGroupIdx = ridx ?? 0;
      });
      if (cid != null && cid != 3152) {
        _qqPlaylists = widget.controller.external.qqPlaylists(categoryId: cid);
      }
    } catch (_) {}
  }

  void _saveCategory(int v) {
    SharedPreferences.getInstance()
        .then((p) => p.setInt('qq_category_id', v))
        .catchError((_) {});
  }

  void _saveRadioGroup(int v) {
    SharedPreferences.getInstance()
        .then((p) => p.setInt('qq_radio_group_idx', v))
        .catchError((_) {});
  }

  void _load() {
    final ext = widget.controller.external;
    // 真实排行榜：网易云 + （有QQ cookie时）QQ 榜单
    _toplists = _loadToplists();
    // QQ 歌单广场（按当前分类加载，默认流行）
    _qqPlaylists = ext.qqPlaylists(categoryId: _qqCategoryId);
    // QQ 电台列表（匿名接口）
    _qqRadios = ext.qqRadios();
    // 本地推荐
    _localRec = _dailyLocalRec();
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
  /// 过滤老歌（开关开 + 年份可确认且早于阈值时剔除）。
  List<Song> _filterOld(List<Song> songs) =>
      songs.where((s) => !widget.settings.isOld(s)).toList();
  /// 风格为 DJ 的曲目（歌名/歌手/专辑任一带 dj，大小写不敏感）全部过滤，用于榜单/歌单。
  bool _isDj(Song s) {
    bool hit(String? v) {
      if (v == null || v.isEmpty) return false;
      final l = v.toLowerCase();
      return l.contains('dj');
    }
    return hit(s.title) || hit(s.artist) || hit(s.album);
  }
  List<Song> _filterBlacklist(List<Song> songs) =>
      songs
          .where((s) => !widget.settings.isBlacklisted(s) && !_isDj(s))
          .toList();

  /// 本地推荐：按日期播种 + 当天缓存，每天变化（同日内稳定）。
  DateTime _localRecDay = DateTime(2000);
  List<Song> _localRecCached = const [];
  Future<List<Song>> _dailyLocalRec() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_localRecDay == today && _localRecCached.isNotEmpty) return _localRecCached;
    final pool = await (_client?.randomSongs(size: 60) ??
            Future.value(<Song>[]))
        .catchError((_) => <Song>[]);
    pool.shuffle(Random(today.year * 10000 + today.month * 100 + today.day));
    final picked = _filterBlacklist(_filterOld(pool.take(30).toList()));
    _localRecDay = today;
    _localRecCached = picked;
    return picked;
  }

  void _onSettingsChanged() {
    if (widget.settings.blacklistRev != _lastBlRev) {
      _lastBlRev = widget.settings.blacklistRev;
      _reload(); // 黑名单变化 → 重载每日30首/榜单/歌单
    }
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  Future<void> _reload() async {
    _load();
    await Future.wait([_toplists, _qqPlaylists, _qqRadios]);
  }

  Future<void> _playSongs(List<Song> songs, int index, {String? source}) async {
    // 先触发跳播放界面（不阻塞），再并行设置队列并播放。
    // 避免 playQueue 偶发解析卡住时 await 阻塞导致"点了歌不跳转"。
    if (context.mounted) {
      unawaited(openPlayerPage(
          context, settings: widget.settings, controller: widget.controller));
    }
    try {
      await widget.controller.playQueue(songs, index, source: source ?? 'QQ音乐');
    } catch (_) {
      // 播放失败也继续进播放界面，避免卡在列表页
    }
    if (mounted) setState(() {});
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
          onPlay: (i) => _playSongs(songs, i, source: name),
        ),
      ));
      return;
    }
    final ext = widget.controller.external;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    List<Song> fetched;
    String? error;
    try {
      fetched = _filterBlacklist(_filterOld(await ext.getPlaylistSongs(playlistId).timeout(const Duration(seconds: 20))));
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
        onPlay: (i) => _playSongs(fetched, i, source: name),
      ),
    ));
  }

  /// QQ 榜单详情：拉 QQ 榜单歌曲（songmid），进列表页，播放走 QQ（带 cookie）。
  Future<void> _openQqToplist(String name, String id, String? coverUrl) async {
    final ext = widget.controller.external;
    final cookie = widget.settings.qqCookie;
    final songs = _filterBlacklist(_filterOld(await ext.qqToplistSongs(id, cookie: cookie, limit: 50)));
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PlaylistDetail(
        title: name,
        songs: songs,
        client: _client,
        settings: widget.settings,
        controller: widget.controller,
        coverUrl: coverUrl,
        onPlay: (i) => _playSongs(songs, i, source: name),
      ),
    ));
  }

  /// QQ 精选歌单详情：qzone 老接口拉歌曲（songmid），进列表页，播放走 QQ→网易云/酷我兜底。
  Future<void> _openQqPlaylist(String name, String dissid, [String? coverUrl]) async {
    final ext = widget.controller.external;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    List<Song> songs;
    String? error;
    try {
      songs = _filterBlacklist(_filterOld(await ext.qqPlaylistSongs(dissid, limit: 100).timeout(const Duration(seconds: 20))));
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
        coverUrl: coverUrl,
        error: error,
        onRetry: () => _openQqPlaylist(name, dissid, coverUrl),
        onPlay: (i) => _playSongs(songs, i, source: name),
      ),
    ));
  }

  /// QQ 电台：拉电台推荐歌曲（匿名接口，每电台固定5首），进列表页播放。
  Future<void> _openQqRadio(String name, int radioId, {bool replace = false, String? coverUrl}) async {
    final ext = widget.controller.external;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    List<Song> songs;
    String? error;
    try {
      songs = _filterBlacklist(await ext.qqRadioSongs(radioId).timeout(const Duration(seconds: 20)));
    } catch (e) {
      songs = const [];
      error = '电台歌曲加载失败：$e';
    }
    if (songs.isEmpty && error == null) error = '没有歌曲数据';
    if (!mounted) return;
    Navigator.pop(context);
    final route = MaterialPageRoute(
      builder: (_) => _PlaylistDetail(
        title: name,
        songs: songs,
        client: _client,
        settings: widget.settings,
        controller: widget.controller,
        coverUrl: coverUrl,
        error: error,
        onRetry: () => _openQqRadio(name, radioId, replace: true, coverUrl: coverUrl),
        onPlay: (i) => _playSongs(songs, i, source: 'QQ电台 · $name'),
      ),
    );
    // 重试时替换当前失败页，避免叠加页面导致返回两次
    if (replace) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  }

  /// 每日30首·本地：每天随机30首本地歌，点卡先进歌单列表页。
  Future<void> _openDailyLocal() async {
    final songs = await _dailyLocalRec();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PlaylistDetail(
        title: '每日30首·本地',
        songs: songs,
        client: _client,
        settings: widget.settings,
        controller: widget.controller,
        onPlay: (i) => _playSongs(songs, i, source: '每日30首·本地'),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (context) {
      final mq = MediaQuery.of(context);
      final car = isCarScreen(context);
      final carP = car && mq.size.width < mq.size.height;
      final carLand = car && mq.size.width > mq.size.height;
      final scale = carP ? 1.6 : mq.textScaler.scale(14) / 14;
      return MediaQuery(
        data: mq.copyWith(textScaler: TextScaler.linear(scale)),
        child: BigScreenText(
      child: Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      // 车机横屏：AppBar 高度压到 0，内容延伸到屏幕顶部（车机系统栏在 App 外）
      appBar: AppBar(
        toolbarHeight: carLand ? 0 : kToolbarHeight,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        actions: carLand
            ? []
            : [
                IconButton(
                  tooltip: '搜索',
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SearchPage(settings: widget.settings, controller: widget.controller),
                  )),
                ),
              ],
      ),
      body: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: Stack(
          children: [
      RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            // QQ 电台（匿名接口：电台列表 → 点进拉 5 首推荐歌曲）
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('QQ电台',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    tooltip: '刷新电台',
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    onPressed: () {
                      setState(() => _qqRadios =
                          widget.controller.external.qqRadios());
                    },
                  ),
                ],
              ),
            ),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _qqRadios,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 18, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('电台加载失败：${snap.error}',
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.orange, fontSize: 13)),
                        ),
                      ],
                    ),
                  );
                }
                // 电台按组渲染：下拉菜单选择分组（选择持久化），下方网格卡片（与歌单广场同尺寸同排列）
                final groups = snap.data ?? const <Map<String, dynamic>>[];
                if (groups.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text('电台暂无数据',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                  );
                }
                final gi = _qqRadioGroupIdx >= groups.length ? 0 : _qqRadioGroupIdx;
                final radios = ((groups[gi]['radios'] as List?) ?? const [])
                    .cast<Map<String, dynamic>>();
                final car = isCarScreen(context);
                final carP = car &&
                    MediaQuery.sizeOf(context).width <
                        MediaQuery.sizeOf(context).height;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: gi,
                            borderRadius: BorderRadius.circular(10),
                            isDense: true,
                            icon: const Icon(Icons.arrow_drop_down_rounded),
                            items: [
                              for (var i = 0; i < groups.length; i++)
                                DropdownMenuItem<int>(
                                  value: i,
                                  child: Text(
                                      ((groups[i]['groupName'] as String?) ??
                                          '电台'),
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                ),
                            ],
                            onChanged: (v) {
                              if (v == null || v == gi) return;
                              setState(() => _qqRadioGroupIdx = v);
                              _saveRadioGroup(v);
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GridView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      gridDelegate: carP
                          ? const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 10,
                              childAspectRatio: 0.86)
                          : SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: car ? 176 : 118,
                              mainAxisSpacing: car ? 12 : 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: car ? 0.7 : 0.72),
                      children: [
                        for (final r in radios)
                          _radioCard(
                            (r['name'] as String?) ?? '',
                            int.tryParse(r['id'].toString()) ?? 0,
                            r['coverUrl'] as String?,
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),

            // QQ 精选歌单（用户强烈要求；硬编码 dissid，点进才拉歌曲）
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('QQ歌单',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            // QQ歌单分类切换（歌单广场）：下拉菜单选择分类
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _qqCategoryId,
                    borderRadius: BorderRadius.circular(10),
                    isDense: true,
                    icon: const Icon(Icons.arrow_drop_down_rounded),
                    items: [
                      for (final c in _qqCategories)
                        DropdownMenuItem<int>(
                          value: c['id'] as int,
                          child: Text('${c['name']}',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                    ],
                    onChanged: (v) {
                      if (v == null || v == _qqCategoryId) return;
                      setState(() {
                        _qqCategoryId = v;
                        _qqPlaylists = widget.controller.external
                            .qqPlaylists(categoryId: v);
                      });
                      _saveCategory(v);
                    },
                  ),
                ),
              ),
            ),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _qqPlaylists,
              builder: (context, snap) {
                // [xmusic] 2026-09-30 接口失败时显示原因（便于定位网络/风控/解析问题），
                // 无数据时显示占位提示，绝不回退到用户个人歌单。
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 18, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('歌单广场加载失败：${snap.error}',
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.orange, fontSize: 13)),
                        ),
                      ],
                    ),
                  );
                }
                final list = snap.data ?? const [];
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      children: [
                        Icon(Icons.cloud_off_outlined, size: 18, color: Colors.grey),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('歌单广场暂无数据，点右上角刷新重试',
                              style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ),
                      ],
                    ),
                  );
                }
                final cards = list;
                final _carP = isCarScreen(context) && MediaQuery.sizeOf(context).width < MediaQuery.sizeOf(context).height;
                return GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: _carP
                      ? const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 12, crossAxisSpacing: 10, childAspectRatio: 0.86)
                      : SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: isCarScreen(context) ? 176 : 118, mainAxisSpacing: isCarScreen(context) ? 12 : 10, crossAxisSpacing: 10, childAspectRatio: isCarScreen(context) ? 0.7 : 0.72),
                  children: cards.map((p) => _qqPlaylistCard(
                    p['name'] as String,
                    p['dissid'] as String,
                    p['coverImgUrl'] as String?,
                  )).toList(),
                );
              },
            ),

            // 排行榜网格（QQ音乐榜 → lx精选 → 网易云榜，无总标题）
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _toplists,
              builder: (context, snap) {
                if (!snap.hasData || snap.data!.isEmpty) {
                  // 后台加载中：先渲染占位图标卡（渐变底+榜单图标），数据加载完成自动填充，不再空白/转圈
                  final car = isCarScreen(context);
                  final carP = car && MediaQuery.sizeOf(context).width < MediaQuery.sizeOf(context).height;
                  return GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate: carP
                        ? const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 12, crossAxisSpacing: 10, childAspectRatio: 0.98)
                        : SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: car ? 176 : 118, mainAxisSpacing: car ? 12 : 10, crossAxisSpacing: 10, childAspectRatio: car ? 0.8 : 1.1),
                    children: List.generate(carP ? 9 : 12, (i) {
                      const phs = [
                        [Color(0xFF3A6DF0), Color(0xFF5B8CFA)],
                        [Color(0xFF8E44AD), Color(0xFFB572E8)],
                        [Color(0xFF00A884), Color(0xFF2FB8A0)],
                        [Color(0xFFE67E22), Color(0xFFF0A45A)],
                        [Color(0xFF16A085), Color(0xFF3BC8A8)],
                        [Color(0xFF2980B9), Color(0xFF5FA8E0)],
                      ];
                      final g = phs[i % phs.length];
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                            colors: g,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.queue_music_rounded, color: Colors.white70, size: 26),
                      );
                    }),
                  );
                }
                // 网易云前8 + QQ前4，分两个子板块并标注来源
                final ne = snap.data!.where((t) => t['source'] != 'qq').take(8).toList();
                final qq = snap.data!.where((t) => t['source'] == 'qq').take(4).toList();
                final car = isCarScreen(context);
                final carP = car && MediaQuery.sizeOf(context).width < MediaQuery.sizeOf(context).height;
                Widget grid(List<Map<String, dynamic>> items, String source) {
                  return GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate: carP
                        ? const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 12, crossAxisSpacing: 10, childAspectRatio: 0.98)
                        : SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: car ? 176 : 118, mainAxisSpacing: car ? 12 : 10, crossAxisSpacing: 10, childAspectRatio: car ? 0.8 : 1.1),
                    children: items.map((t) => _toplistCard(
                      t['name'] as String,
                      t['id'] as String,
                      t['coverImgUrl'] as String?,
                      source: source,
                    )).toList(),
                  );
                }
                Widget sectionTitle(String text) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                  child: Text(text,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700, fontSize: 13)),
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionTitle('QQ音乐榜'),
                    grid(qq, 'qq'),
                    sectionTitle('网易云榜'),
                    grid(ne, 'ne'),
                    sectionTitle('LX精选'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GridView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: carP
                            ? const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 12, crossAxisSpacing: 10, childAspectRatio: 0.86)
                            : SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: car ? 176 : 118, mainAxisSpacing: car ? 12 : 10, crossAxisSpacing: 10, childAspectRatio: car ? 0.7 : 0.72),
                        children: ExternalApi.lxPresets.map((p) => _lxCard(p['name']!, p['id']!, p['coverUrl'] as String?)).toList(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
          ),
      ),
          // 车机横屏：搜索按钮浮在右上角（AppBar 高度为 0 后）
          if (carLand)
            Positioned(
              top: 8, right: 8,
              child: IconButton(
                tooltip: '搜索',
                icon: const Icon(Icons.search_rounded),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SearchPage(settings: widget.settings, controller: widget.controller),
                )),
              ),
            ),
          ],
        ),
      ),
    )),
      );
    });
  }

  /// 每日30首小卡（在线/本地两栏）：渐变底 + 图标 + 标题副标题，点击进对应歌单。
  Widget _daily30Card({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> colors,
    String? coverUrl,
    VoidCallback? onTap,
  }) {
    return Material(
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                    clipBehavior: Clip.antiAlias,
                    child: (coverUrl != null && coverUrl!.isNotEmpty)
                        ? Image.network(coverUrl!, width: 36, height: 36, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(icon, color: Colors.white, size: 22))
                        : Icon(icon, color: Colors.white, size: 22),
                  ),
                  const Spacer(),
                  const Icon(Icons.play_arrow_rounded, color: Colors.white70),
                ],
              ),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
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
    // 来源角标文案（网易云/QQ音乐）
    final srcLabel = source == 'qq' ? 'QQ音乐' : '网易云';
    Widget srcBadge() => Positioned(
      left: 4, top: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(srcLabel,
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
      ),
    );
    // [xmusic] 车机横屏参考网易云车机版：方封面 + 下方标题；手机保持原铺满卡。
    if (isCarScreen(context)) {
      final carP = isCarScreen(context) &&
          MediaQuery.sizeOf(context).width < MediaQuery.sizeOf(context).height;
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => source == 'qq'
            ? _openQqToplist(name, id, coverUrl)
            : _openPlaylist(name, id, coverUrl: coverUrl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (carP)
              SizedBox(
                height: 116,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: (coverUrl != null && coverUrl.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: coverUrl,
                              fit: BoxFit.cover,
                              httpHeaders: const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://music.163.com/'},
                              placeholder: (_, __) => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                              errorWidget: (_, __, ___) => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                            )
                          : Container(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.all(8),
                              child: Text(name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w700)),
                            ),
                    ),
                    srcBadge(),
                  ],
                ),
              )
            else
              SizedBox(
                height: 132,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: (coverUrl != null && coverUrl.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: coverUrl,
                              fit: BoxFit.cover,
                              httpHeaders: const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://music.163.com/'},
                              placeholder: (_, __) => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                              errorWidget: (_, __, ___) => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                            )
                          : Container(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.all(8),
                              child: Text(name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w700)),
                            ),
                    ),
                    srcBadge(),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w500)),
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
                  httpHeaders: _imgHeaders(coverUrl!),
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
  /// QQ 精选歌单卡：方形圆角封面 + 下方标题（文字放图下完整显示，不叠在图上截断；横竖屏同排布）。
  /// QQ 电台卡（与歌单广场同尺寸同排列）：圆角方块封面 + 下方电台名，点击进电台歌曲。
  Widget _radioCard(String name, int id, String? coverUrl) {
    final theme = Theme.of(context);
    final carP = isCarScreen(context) &&
        MediaQuery.sizeOf(context).width < MediaQuery.sizeOf(context).height;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => id > 0 ? _openQqRadio(name, id, coverUrl: coverUrl) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isCarScreen(context))
            SizedBox(
              height: carP ? 116 : 132,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: (coverUrl != null && coverUrl.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        httpHeaders: const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://y.qq.com/'},
                        placeholder: (_, __) => Container(color: theme.colorScheme.surfaceContainerHighest),
                        errorWidget: (_, __, ___) => Container(color: theme.colorScheme.surfaceContainerHighest),
                      )
                    : Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Icon(Icons.radio_rounded, color: theme.colorScheme.onSurfaceVariant),
                      ),
              ),
            )
          else
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: (coverUrl != null && coverUrl.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        httpHeaders: const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://y.qq.com/'},
                        placeholder: (_, __) => Container(color: theme.colorScheme.surfaceContainerHighest),
                        errorWidget: (_, __, ___) => Container(color: theme.colorScheme.surfaceContainerHighest),
                      )
                    : Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Icon(Icons.radio_rounded, color: theme.colorScheme.onSurfaceVariant),
                      ),
              ),
            ),
          const SizedBox(height: 6),
          Text(name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w500, height: 1.25)),
        ],
      ),
    );
  }

  Widget _qqPlaylistCard(String name, String dissid, String? coverUrl) {
    final theme = Theme.of(context);
    final carP = isCarScreen(context) &&
        MediaQuery.sizeOf(context).width < MediaQuery.sizeOf(context).height;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openQqPlaylist(name, dissid, coverUrl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isCarScreen(context))
            SizedBox(
              height: carP ? 116 : 132,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: (coverUrl != null && coverUrl.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        httpHeaders: const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://y.qq.com/'},
                        placeholder: (_, __) => Container(color: theme.colorScheme.surfaceContainerHighest),
                        errorWidget: (_, __, ___) => Container(color: theme.colorScheme.surfaceContainerHighest),
                      )
                    : Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Icon(Icons.queue_music_rounded, color: theme.colorScheme.onSurfaceVariant),
                      ),
              ),
            )
          else
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: (coverUrl != null && coverUrl.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        httpHeaders: const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://y.qq.com/'},
                        placeholder: (_, __) => Container(color: theme.colorScheme.surfaceContainerHighest),
                        errorWidget: (_, __, ___) => Container(color: theme.colorScheme.surfaceContainerHighest),
                      )
                    : Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Icon(Icons.queue_music_rounded, color: theme.colorScheme.onSurfaceVariant),
                      ),
              ),
            ),
          const SizedBox(height: 6),
          Text(name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w500, height: 1.25)),
        ],
      ),
    );
  }

  /// LX 精选卡（网易云榜单/精选歌单，meting 先行版）：真实封面(可回退渐变) + 下方标题。
  Widget _lxCard(String name, String id, String? coverUrl) {
    final theme = Theme.of(context);
    final carP = isCarScreen(context) &&
        MediaQuery.sizeOf(context).width < MediaQuery.sizeOf(context).height;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openLxPlaylist(name, id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isCarScreen(context))
            SizedBox(
              height: carP ? 116 : 132,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: (coverUrl != null && coverUrl.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        httpHeaders: const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://music.163.com/'},
                        placeholder: (_, __) => Container(color: theme.colorScheme.surfaceContainerHighest),
                        errorWidget: (_, __, ___) => Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                              colors: [Color(0xFF1F2733), Color(0xFF3A4A5F)],
                            ),
                          ),
                          child: const Icon(Icons.album_rounded, color: Colors.white70, size: 34),
                        ),
                      )
                    : Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                            colors: [Color(0xFF1F2733), Color(0xFF3A4A5F)],
                          ),
                        ),
                        child: const Icon(Icons.album_rounded, color: Colors.white70, size: 34),
                      ),
              ),
            )
          else
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: (coverUrl != null && coverUrl.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        httpHeaders: const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://music.163.com/'},
                        placeholder: (_, __) => Container(color: theme.colorScheme.surfaceContainerHighest),
                        errorWidget: (_, __, ___) => Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                              colors: [Color(0xFF1F2733), Color(0xFF3A4A5F)],
                            ),
                          ),
                          child: const Icon(Icons.album_rounded, color: Colors.white70, size: 34),
                        ),
                      )
                    : Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                            colors: [Color(0xFF1F2733), Color(0xFF3A4A5F)],
                          ),
                        ),
                        child: const Icon(Icons.album_rounded, color: Colors.white70, size: 34),
                      ),
              ),
            ),
          const SizedBox(height: 6),
          Text(name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w500, height: 1.25)),
        ],
      ),
    );
  }

  /// LX 精选歌单/榜单详情：meting 拉歌曲（已带直链），进列表页直接播放。
  Future<void> _openLxPlaylist(String name, String id) async {
    final ext = widget.controller.external;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    List<Song> songs;
    String? error;
    try {
      songs = await ext.lxMetingPlaylistSongs(id).timeout(const Duration(seconds: 20));
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
        coverUrl: songs.isNotEmpty ? songs.first.coverUrl : null,
        error: error,
        onRetry: () => _openLxPlaylist(name, id),
        onPlay: (i) => _playSongs(songs, i, source: name),
      ),
    ));
  }

}

/// 歌单详情页（支持左滑删除歌曲，移除记录按歌单名本地持久化）
class _PlaylistDetail extends StatefulWidget {
  const _PlaylistDetail({
    required this.title,
    required this.songs,
    required this.client,
    required this.settings,
    required this.controller,
    required this.onPlay,
    this.coverUrl,
    this.error,
    this.onRetry,
  });

  final String title;
  final List<Song> songs;
  final SubsonicClient? client;
  final AppSettings settings;
  final PlayerController controller;
  final void Function(int index) onPlay;
  final String? coverUrl;
  final String? error;
  final VoidCallback? onRetry;

  @override
  State<_PlaylistDetail> createState() => _PlaylistDetailState();
}

class _PlaylistDetailState extends State<_PlaylistDetail> {
  Set<String> _removed = <String>{};

  @override
  void initState() {
    super.initState();
    _loadRemoved();
  }

  Future<void> _loadRemoved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'playlist_removed_${widget.title}';
      final list = prefs.getStringList(key) ?? const <String>[];
      if (!mounted) return;
      setState(() => _removed = list.toSet());
    } catch (_) {}
  }

  Future<void> _removeSong(Song song) async {
    setState(() => _removed = {..._removed, song.id});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          'playlist_removed_${widget.title}', _removed.toList());
    } catch (_) {}
  }

  /// 未被移除的歌曲在原始列表中的索引（onPlay 需要原始索引）
  List<int> get _visibleIndices {
    final out = <int>[];
    for (var i = 0; i < widget.songs.length; i++) {
      if (!_removed.contains(widget.songs[i].id)) out.add(i);
    }
    return out;
  }

  /// 下载整个歌单到 NAS（WebDAV）：逐首上传，对话框显示进度，结束汇总结果。
  Future<void> _downloadAllToNas() async {
    if (!widget.settings.webdavConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('未配置 NAS (WebDAV)，请到 设置-个性化 中配置')));
      return;
    }
    final songs = widget.songs
        .where((s) => !_removed.contains(s.id))
        .toList();
    if (songs.isEmpty) return;
    var done = 0;
    var ok = 0;
    String? firstErr;
    void Function(void Function())? setDlg;
    // 弹出进度对话框（StatefulBuilder 让进度能刷新）
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          setDlg = set;
          return AlertDialog(
            title: const Text('下载到 NAS'),
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 16),
                Text('正在上传 $done/${songs.length}…'),
              ],
            ),
          );
        },
      ),
    );
    for (final s in songs) {
      final r = await widget.controller.uploadSongToNas(s, folder: widget.title);
      done++;
      if (r.startsWith('已上传')) {
        ok++;
      } else {
        firstErr ??= r;
      }
      setDlg?.call(() {});
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // 关闭进度框
    final summary = ok == songs.length
        ? '已上传全部 $ok 首到 NAS'
        : '完成：成功 $ok/${songs.length} 首' +
            (firstErr != null ? '，失败示例：$firstErr' : '');
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(summary)));
  }

  @override
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
    // 背景封面：列表第一首有封面歌曲优先，入口封面兜底。
    // QQ 封面 URL 带尺寸段（T002R80x80 等），小封面全屏模糊后颜色极淡、观感接近纯白，
    // 统一放大到 T002R500x500，保证模糊背景颜色明显（与音乐库当前歌曲大封面观感一致）。
    final fbUrl = songs.isNotEmpty
        ? (songs.first.coverUrl != null && songs.first.coverUrl!.isNotEmpty
            ? songs.first.coverUrl
            : (songs.first.coverArt != null && songs.first.coverArt!.isNotEmpty
                ? client?.coverUrl(songs.first.coverArt!, size: 600)?.toString()
                : null))
        : null;
    String bigCover(String? u) {
      if (u == null || u.isEmpty) return u ?? '';
      return u.replaceFirstMapped(
          RegExp(r'T002R\d+x\d+'), (_) => 'T002R500x500');
    }

    final bgUrl = bigCover(fbUrl ?? coverUrl);
    // [xmusic] 背景与全局统一：PageBackground（当前播放封面模糊玻璃），
    // 与音乐库/搜索/歌手等页面完全一致；fallback 用歌单封面兜底。
    return PageBackground(
      controller: controller,
      settings: settings,
      fallbackCoverUrl: bgUrl,
      child: BigScreenText(
        child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: (Theme.of(context).brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark)
                .copyWith(
                    statusBarColor: settings.coverColorBg
                        ? Colors.transparent
                        : Theme.of(context).colorScheme.surfaceContainer),
            child: Scaffold(
        backgroundColor: Colors.transparent,
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(title)),
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
                      httpHeaders: _imgHeaders(coverUrl!),
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
                TextButton.icon(
                  onPressed: _visibleIndices.isEmpty || error != null ? null : () {
                    songs.shuffle();
                    onPlay(0);
                  },
                  icon: const Icon(Icons.shuffle_rounded, size: 20),
                  label: const Text('随机'),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10)),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: _visibleIndices.isEmpty || error != null ? null : () => onPlay(0),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('顺序'),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10)),
                ),
                const SizedBox(width: 4),
                if (!isCarScreen(context))
                  TextButton.icon(
                    onPressed: _visibleIndices.isEmpty || error != null
                        ? null
                        : _downloadAllToNas,
                    icon: const Icon(Icons.cloud_download_rounded, size: 20),
                    label: const Text('全部下载'),
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10)),
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
                      return SongTile(
                        song: song,
                        client: client,
                        onTap: () => onPlay(i),
                        onFavorite: () async {
                          final s = song;
                          if (!s.fromExternal) {
                            try {
                              s.starred
                                  ? await client?.unstarSong(s.id)
                                  : await client?.starSong(s.id);
                            } catch (_) {}
                          }
                        },
                        blacklisted: widget.settings.isBlacklisted(song),
                        onBlacklist: () async {
                          final s = song;
                          if (widget.settings.isBlacklisted(s)) {
                            await widget.settings.removeBlacklist(s);
                          } else {
                            await widget.settings.addBlacklist(s);
                          }
                        },
                        onDelete: () => _removeSong(song),
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
        )),
        ),
        ),
      );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.song, required this.client, required this.onTap});
  final Song song;
  final SubsonicClient? client;
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

Map<String, String> _imgHeaders(String u) {
  final host = Uri.parse(u).host.toLowerCase();
  if (host.contains('qq.com') || host.contains('gtimg.cn')) {
    return const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://y.qq.com/'};
  }
  if (host.contains('163') || host.contains('126.net')) {
    return const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://music.163.com/'};
  }
  return const {'User-Agent': 'Mozilla/5.0'};
}
