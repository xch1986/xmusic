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
  int _qqCategoryId = 3152; // QQ姝屽崟鍒嗙被锛?152娴佽/41鎽囨粴/48姘戣埃/45鐢靛瓙/42璇村敱/61鍙ら/49绾煶涔?46鐖靛＋/43R&B/47鍙ゅ吀
  int _qqRadioGroupIdx = 0; // QQ鐢靛彴鍒嗙粍涓嬫媺褰撳墠閫変腑缁勭储寮?
  static const List<Map<String, dynamic>> _qqCategories = [
    {'id': 3152, 'name': '娴佽'},
    {'id': 41, 'name': '鎽囨粴'},
    {'id': 48, 'name': '姘戣埃'},
    {'id': 45, 'name': '鐢靛瓙'},
    {'id': 61, 'name': '鍙ら'},
    {'id': 49, 'name': '杞婚煶涔?},
    {'id': 46, 'name': '鐖靛＋'},
    {'id': 43, 'name': 'R&B'},
    {'id': 47, 'name': '鍙ゅ吀'},
    {'id': 68, 'name': '涓浗椋?},
    {'id': 59, 'name': '缁忓吀'},
    {'id': 44, 'name': '涔℃潙'},
    {'id': 51, 'name': '钃濊皟'},
    {'id': 53, 'name': '鏂颁笘绾?},
    {'id': 64, 'name': 'KTV鐑瓕'},
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

  /// 鎭㈠姝屽崟骞垮満鍒嗙被 / QQ鐢靛彴鍒嗙粍鐨勪笅鎷夐€夋嫨锛堢敤鎴疯姹備笅娆″惎鍔ㄨ浣忥級
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
    // 鐪熷疄鎺掕姒滐細缃戞槗浜?+ 锛堟湁QQ cookie鏃讹級QQ 姒滃崟
    _toplists = _loadToplists();
    // QQ 姝屽崟骞垮満锛堟寜褰撳墠鍒嗙被鍔犺浇锛岄粯璁ゆ祦琛岋級
    _qqPlaylists = ext.qqPlaylists(categoryId: _qqCategoryId);
    // QQ 鐢靛彴鍒楄〃锛堝尶鍚嶆帴鍙ｏ級
    _qqRadios = ext.qqRadios();
    // 鏈湴鎺ㄨ崘
    _localRec = _dailyLocalRec();
  }

  /// 鎺掕姒滐細缃戞槗浜戞鍗?+ QQ 鐑/鏂版瓕姒?椋欏崌姒?娴佽鎸囨暟姒滄贩鎺掞紙缃戞槗浜戝墠8 + QQ鍓?锛夈€?
  /// [xmusic] 2026-09-24 淇锛歈Q 姒滃崟鏁版嵁鎺ュ彛鍖垮悕鍙敤锛坒cg_v8_toplist_cp锛夛紝
  /// 涓嶅啀渚濊禆 QQ cookie 鎵嶆樉绀衡€斺€旇溅鏈?鏈～ cookie 涔熻兘鐪嬪埌 QQ 鍥涘ぇ姒滐紱
  /// 鏈?cookie 鏃剁偣杩涙鍗曡蛋 QQ 闊虫簮鎾斁锛屾棤 cookie 鏃剁敱鎾斁閾剧綉鏄撲簯/閰锋垜鍏滃簳銆?
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

  /// 姣忔棩30棣栵細璁剧疆浜?QQ cookie 鐢?QQ 鐑瓕姒滐紙鎾斁璧?QQ锛夛紱鍚﹀垯閰风嫍TOP500 鈫?缃戞槗浜戝尮閰嶆挱鏀俱€?
  /// 杩囨护鑰佹瓕锛堝紑鍏冲紑 + 骞翠唤鍙‘璁や笖鏃╀簬闃堝€兼椂鍓旈櫎锛夈€?
  List<Song> _filterOld(List<Song> songs) =>
      songs.where((s) => !widget.settings.isOld(s)).toList();
  /// 椋庢牸涓?DJ 鐨勬洸鐩紙姝屽悕/姝屾墜/涓撹緫浠讳竴甯?dj锛屽ぇ灏忓啓涓嶆晱鎰燂級鍏ㄩ儴杩囨护锛岀敤浜庢鍗?姝屽崟銆?
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

  /// 鏈湴鎺ㄨ崘锛氭寜鏃ユ湡鎾 + 褰撳ぉ缂撳瓨锛屾瘡澶╁彉鍖栵紙鍚屾棩鍐呯ǔ瀹氾級銆?
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
      _reload(); // 榛戝悕鍗曞彉鍖?鈫?閲嶈浇姣忔棩30棣?姒滃崟/姝屽崟
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
    // 鍏堣Е鍙戣烦鎾斁鐣岄潰锛堜笉闃诲锛夛紝鍐嶅苟琛岃缃槦鍒楀苟鎾斁銆?
    // 閬垮厤 playQueue 鍋跺彂瑙ｆ瀽鍗′綇鏃?await 闃诲瀵艰嚧"鐐逛簡姝屼笉璺宠浆"銆?
    if (context.mounted) {
      unawaited(openPlayerPage(
          context, settings: widget.settings, controller: widget.controller));
    }
    try {
      await widget.controller.playQueue(songs, index, source: source ?? 'QQ闊充箰');
    } catch (_) {
      // 鎾斁澶辫触涔熺户缁繘鎾斁鐣岄潰锛岄伩鍏嶅崱鍦ㄥ垪琛ㄩ〉
    }
    if (mounted) setState(() {});
  }

  Future<void> _openPlaylist(String name, String playlistId,
      {String? coverUrl, List<Song>? songs}) async {
    // 宸叉湁鏁版嵁锛堝鐑瓕姒滃ぇ鍗＄墖棣栭〉宸插姞杞斤級锛氱洿鎺ヨ繘璇︽儏椤碉紝绉掑紑涓嶈浆鍦堛€佷笉鍐嶄簩娆¤姹?
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
      error = '鍔犺浇澶辫触锛?e锛?;
    }
    if (fetched.isEmpty && error == null) error = '娌℃湁姝屾洸鏁版嵁';
    if (!mounted) return;
    Navigator.pop(context); // dismiss loading
    // 鏃犺鎴愯触閮借繘鍏ヨ鎯呴〉锛氬け璐ユ樉绀哄師鍥?閲嶈瘯锛岀粷涓嶇┖鐧介〉鎴栨棤澹拌繑鍥?
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

  /// QQ 姒滃崟璇︽儏锛氭媺 QQ 姒滃崟姝屾洸锛坰ongmid锛夛紝杩涘垪琛ㄩ〉锛屾挱鏀捐蛋 QQ锛堝甫 cookie锛夈€?
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

  /// QQ 绮鹃€夋瓕鍗曡鎯咃細qzone 鑰佹帴鍙ｆ媺姝屾洸锛坰ongmid锛夛紝杩涘垪琛ㄩ〉锛屾挱鏀捐蛋 QQ鈫掔綉鏄撲簯/閰锋垜鍏滃簳銆?
  Future<void> _openQqPlaylist(String name, String dissid, [String? coverUrl]) async {
    final ext = widget.controller.external;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    List<Song> songs;
    String? error;
    try {
      songs = _filterBlacklist(_filterOld(await ext.qqPlaylistSongs(dissid, limit: 100).timeout(const Duration(seconds: 20))));
    } catch (e) {
      songs = const [];
      error = '鍔犺浇澶辫触锛?e锛?;
    }
    if (songs.isEmpty && error == null) error = '娌℃湁姝屾洸鏁版嵁';
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

  /// QQ 鐢靛彴锛氭媺鐢靛彴鎺ㄨ崘姝屾洸锛堝尶鍚嶆帴鍙ｏ紝姣忕數鍙板浐瀹?棣栵級锛岃繘鍒楄〃椤垫挱鏀俱€?
  Future<void> _openQqRadio(String name, int radioId, {bool replace = false, String? coverUrl}) async {
    final ext = widget.controller.external;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    List<Song> songs;
    String? error;
    try {
      songs = _filterBlacklist(await ext.qqRadioSongs(radioId).timeout(const Duration(seconds: 20)));
    } catch (e) {
      songs = const [];
      error = '鐢靛彴姝屾洸鍔犺浇澶辫触锛?e';
    }
    if (songs.isEmpty && error == null) error = '娌℃湁姝屾洸鏁版嵁';
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
        onPlay: (i) => _playSongs(songs, i, source: 'QQ鐢靛彴 路 $name'),
      ),
    );
    // 閲嶈瘯鏃舵浛鎹㈠綋鍓嶅け璐ラ〉锛岄伩鍏嶅彔鍔犻〉闈㈠鑷磋繑鍥炰袱娆?
    if (replace) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  }

  /// 姣忔棩30棣柭锋湰鍦帮細姣忓ぉ闅忔満30棣栨湰鍦版瓕锛岀偣鍗″厛杩涙瓕鍗曞垪琛ㄩ〉銆?
  Future<void> _openDailyLocal() async {
    final songs = await _dailyLocalRec();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PlaylistDetail(
        title: '姣忔棩30棣柭锋湰鍦?,
        songs: songs,
        client: _client,
        settings: widget.settings,
        controller: widget.controller,
        onPlay: (i) => _playSongs(songs, i, source: '姣忔棩30棣柭锋湰鍦?),
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
      // 杞︽満妯睆锛欰ppBar 楂樺害鍘嬪埌 0锛屽唴瀹瑰欢浼稿埌灞忓箷椤堕儴锛堣溅鏈虹郴缁熸爮鍦?App 澶栵級
      appBar: AppBar(
        toolbarHeight: carLand ? 0 : kToolbarHeight,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        actions: carLand
            ? []
            : [
                IconButton(
                  tooltip: '鎼滅储',
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SearchPage(settings: widget.settings, controller: widget.controller),
                  )),
                ),
              ],
      ),
      body: Stack(
        children: [
      RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            // QQ 鐢靛彴锛堝尶鍚嶆帴鍙ｏ細鐢靛彴鍒楄〃 鈫?鐐硅繘鎷?5 棣栨帹鑽愭瓕鏇诧級
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('QQ鐢靛彴',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    tooltip: '鍒锋柊鐢靛彴',
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
                          child: Text('鐢靛彴鍔犺浇澶辫触锛?{snap.error}',
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.orange, fontSize: 13)),
                        ),
                      ],
                    ),
                  );
                }
                // 鐢靛彴鎸夌粍娓叉煋锛氫笅鎷夎彍鍗曢€夋嫨鍒嗙粍锛堥€夋嫨鎸佷箙鍖栵級锛屼笅鏂圭綉鏍煎崱鐗囷紙涓庢瓕鍗曞箍鍦哄悓灏哄鍚屾帓鍒楋級
                final groups = snap.data ?? const <Map<String, dynamic>>[];
                if (groups.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text('鐢靛彴鏆傛棤鏁版嵁',
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
                                          '鐢靛彴'),
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

            // QQ 绮鹃€夋瓕鍗曪紙鐢ㄦ埛寮虹儓瑕佹眰锛涚‖缂栫爜 dissid锛岀偣杩涙墠鎷夋瓕鏇诧級
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('QQ姝屽崟',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            // QQ姝屽崟鍒嗙被鍒囨崲锛堟瓕鍗曞箍鍦猴級锛氫笅鎷夎彍鍗曢€夋嫨鍒嗙被
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
                // [xmusic] 2026-09-30 鎺ュ彛澶辫触鏃舵樉绀哄師鍥狅紙渚夸簬瀹氫綅缃戠粶/椋庢帶/瑙ｆ瀽闂锛夛紝
                // 鏃犳暟鎹椂鏄剧ず鍗犱綅鎻愮ず锛岀粷涓嶅洖閫€鍒扮敤鎴蜂釜浜烘瓕鍗曘€?
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 18, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('姝屽崟骞垮満鍔犺浇澶辫触锛?{snap.error}',
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
                          child: Text('姝屽崟骞垮満鏆傛棤鏁版嵁锛岀偣鍙充笂瑙掑埛鏂伴噸璇?,
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

            // 鎺掕姒滅綉鏍硷紙QQ闊充箰姒?鈫?lx绮鹃€?鈫?缃戞槗浜戞锛屾棤鎬绘爣棰橈級
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _toplists,
              builder: (context, snap) {
                if (!snap.hasData || snap.data!.isEmpty) {
                  // 鍚庡彴鍔犺浇涓細鍏堟覆鏌撳崰浣嶅浘鏍囧崱锛堟笎鍙樺簳+姒滃崟鍥炬爣锛夛紝鏁版嵁鍔犺浇瀹屾垚鑷姩濉厖锛屼笉鍐嶇┖鐧?杞湀
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
                // 缃戞槗浜戝墠8 + QQ鍓?锛屽垎涓や釜瀛愭澘鍧楀苟鏍囨敞鏉ユ簮
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
                    sectionTitle('QQ闊充箰姒?),
                    grid(qq, 'qq'),
                    sectionTitle('缃戞槗浜戞'),
                    grid(ne, 'ne'),
                    sectionTitle('LX绮鹃€?),
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
          // 杞︽満妯睆锛氭悳绱㈡寜閽诞鍦ㄥ彸涓婅锛圓ppBar 楂樺害涓?0 鍚庯級
          if (carLand)
            Positioned(
              top: 8, right: 8,
              child: IconButton(
                tooltip: '鎼滅储',
                icon: const Icon(Icons.search_rounded),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SearchPage(settings: widget.settings, controller: widget.controller),
                )),
              ),
            ),
        ],
      ),
    )),
      );
    });
  }

  /// 姣忔棩30棣栧皬鍗★紙鍦ㄧ嚎/鏈湴涓ゆ爮锛夛細娓愬彉搴?+ 鍥炬爣 + 鏍囬鍓爣棰橈紝鐐瑰嚮杩涘搴旀瓕鍗曘€?
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

  /// 鍗婂姝屽崟鍗★紙鏈湴鎺ㄨ崘锛夛細娓愬彉搴?+ 鍥炬爣 + 鏍囬 + 鍓爣棰橈紝鐐瑰嚮杩涙瓕鍗曢〉銆?
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
    // 鏉ユ簮瑙掓爣鏂囨锛堢綉鏄撲簯/QQ闊充箰锛?
    final srcLabel = source == 'qq' ? 'QQ闊充箰' : '缃戞槗浜?;
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
    // [xmusic] 杞︽満妯睆鍙傝€冪綉鏄撲簯杞︽満鐗堬細鏂瑰皝闈?+ 涓嬫柟鏍囬锛涙墜鏈轰繚鎸佸師閾烘弧鍗°€?
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
                // QQ 姒滃崟绛夋棤灏侀潰锛氭笎鍙樺簳 + 姒滃崟鍚嶆枃瀛楋紝涓嶅啀鍙樉绀虹伆鍧?
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
  /// QQ 绮鹃€夋瓕鍗曞崱锛氭柟褰㈠渾瑙掑皝闈?+ 涓嬫柟鏍囬锛堟枃瀛楁斁鍥句笅瀹屾暣鏄剧ず锛屼笉鍙犲湪鍥句笂鎴柇锛涙í绔栧睆鍚屾帓甯冿級銆?
  /// QQ 鐢靛彴鍗★紙涓庢瓕鍗曞箍鍦哄悓灏哄鍚屾帓鍒楋級锛氬渾瑙掓柟鍧楀皝闈?+ 涓嬫柟鐢靛彴鍚嶏紝鐐瑰嚮杩涚數鍙版瓕鏇层€?
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

  /// LX 绮鹃€夊崱锛堢綉鏄撲簯姒滃崟/绮鹃€夋瓕鍗曪紝meting 鍏堣鐗堬級锛氱湡瀹炲皝闈?鍙洖閫€娓愬彉) + 涓嬫柟鏍囬銆?
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

  /// LX 绮鹃€夋瓕鍗?姒滃崟璇︽儏锛歮eting 鎷夋瓕鏇诧紙宸插甫鐩撮摼锛夛紝杩涘垪琛ㄩ〉鐩存帴鎾斁銆?
  Future<void> _openLxPlaylist(String name, String id) async {
    final ext = widget.controller.external;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    List<Song> songs;
    String? error;
    try {
      songs = await ext.lxMetingPlaylistSongs(id).timeout(const Duration(seconds: 20));
    } catch (e) {
      songs = const [];
      error = '鍔犺浇澶辫触锛?e锛?;
    }
    if (songs.isEmpty && error == null) error = '娌℃湁姝屾洸鏁版嵁';
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

/// 姝屽崟璇︽儏椤碉紙鏀寔宸︽粦鍒犻櫎姝屾洸锛岀Щ闄よ褰曟寜姝屽崟鍚嶆湰鍦版寔涔呭寲锛?
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

  /// 鏈绉婚櫎鐨勬瓕鏇插湪鍘熷鍒楄〃涓殑绱㈠紩锛坥nPlay 闇€瑕佸師濮嬬储寮曪級
  List<int> get _visibleIndices {
    final out = <int>[];
    for (var i = 0; i < widget.songs.length; i++) {
      if (!_removed.contains(widget.songs[i].id)) out.add(i);
    }
    return out;
  }

  /// 涓嬭浇鏁翠釜姝屽崟鍒?NAS锛圵ebDAV锛夛細閫愰涓婁紶锛屽璇濇鏄剧ず杩涘害锛岀粨鏉熸眹鎬荤粨鏋溿€?
  Future<void> _downloadAllToNas() async {
    if (!widget.settings.webdavConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('鏈厤缃?NAS (WebDAV)锛岃鍒?璁剧疆-涓€у寲 涓厤缃?)));
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
    // 寮瑰嚭杩涘害瀵硅瘽妗嗭紙StatefulBuilder 璁╄繘搴﹁兘鍒锋柊锛?
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          setDlg = set;
          return AlertDialog(
            title: const Text('涓嬭浇鍒?NAS'),
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 16),
                Text('姝ｅ湪涓婁紶 $done/${songs.length}鈥?),
              ],
            ),
          );
        },
      ),
    );
    for (final s in songs) {
      final r = await widget.controller.uploadSongToNas(s, folder: widget.title);
      done++;
      if (r.startsWith('宸蹭笂浼?)) {
        ok++;
      } else {
        firstErr ??= r;
      }
      setDlg?.call(() {});
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // 鍏抽棴杩涘害妗?
    final summary = ok == songs.length
        ? '宸蹭笂浼犲叏閮?$ok 棣栧埌 NAS'
        : '瀹屾垚锛氭垚鍔?$ok/${songs.length} 棣? +
            (firstErr != null ? '锛屽け璐ョず渚嬶細$firstErr' : '');
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
    // 鑳屾櫙灏侀潰锛氬垪琛ㄧ涓€棣栨湁灏侀潰姝屾洸浼樺厛锛屽叆鍙ｅ皝闈㈠厹搴曘€?
    // QQ 灏侀潰 URL 甯﹀昂瀵告锛圱002R80x80 绛夛級锛屽皬灏侀潰鍏ㄥ睆妯＄硦鍚庨鑹叉瀬娣°€佽鎰熸帴杩戠函鐧斤紝
    // 缁熶竴鏀惧ぇ鍒?T002R500x500锛屼繚璇佹ā绯婅儗鏅鑹叉槑鏄撅紙涓庨煶涔愬簱褰撳墠姝屾洸澶у皝闈㈣鎰熶竴鑷达級銆?
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
    // [xmusic] 鑳屾櫙涓庡叏灞€缁熶竴锛歅ageBackground锛堝綋鍓嶆挱鏀惧皝闈㈡ā绯婄幓鐠冿級锛?
    // 涓庨煶涔愬簱/鎼滅储/姝屾墜绛夐〉闈㈠畬鍏ㄤ竴鑷达紱fallback 鐢ㄦ瓕鍗曞皝闈㈠厹搴曘€?
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
                        Text('鍏?${_visibleIndices.length} 棣?, style: Theme.of(context).textTheme.bodyMedium),
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
                  label: const Text('闅忔満'),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10)),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: _visibleIndices.isEmpty || error != null ? null : () => onPlay(0),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('椤哄簭'),
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
                    label: const Text('鍏ㄩ儴涓嬭浇'),
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
                          label: const Text('閲嶈瘯'),
                        ),
                    ],
                  ),
                )
              : _visibleIndices.isEmpty
                ? const Center(child: Text('宸插叏閮ㄧЩ闄?))
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
        // 杩蜂綘鎾斁鏉℃斁 body 搴曢儴鑰屼笉鏄?bottomNavigationBar锛?
        // 閬垮厤涓埆璁惧涓?bottomNavigationBar 妲戒綅鎶婅糠浣犳潯鎾戞弧鍏ㄥ睆銆佹尋娌″垪琛紙0.2.x 淇鍥炲綊锛?
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
