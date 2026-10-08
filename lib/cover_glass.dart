import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'player_controller.dart';
import 'settings.dart';

/// 全局封面玻璃背景：开启「封面颜色(封面透出)」后，首页/音乐库/搜索/设置/播放页等
/// 页面背景透出**当前播放歌曲的封面图片**（玻璃质感、随切歌自动更新）；
/// 未开启时回退手动背景色或主题表面，外观与原先一致。
class CoverGlassBackground extends StatelessWidget {
  const CoverGlassBackground({super.key, required this.controller, required this.settings, this.fallbackCoverUrl});

  final PlayerController controller;
  final AppSettings settings;
  final String? fallbackCoverUrl;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, settings]),
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final isCover = settings.coverColorBg;
        final song = controller.current;
        final customBg = settings.bgColor != 0
            ? Color(settings.bgColor).withValues(alpha: isDark ? 0.55 : 0.78)
            : null;
        // 无封面/封面加载失败时的底色：浅色主题下不直接用纯 F5F5F5（观感纯白），
        // 以主题主色极低比例染色，得到有层次感的浅底（深色主题同样微亮），
        // 保证任何状态下背景都不再是纯白。
        final plainBg = customBg ??
            Color.alphaBlend(
                cs.primary.withValues(alpha: 0.07), cs.surfaceContainer);
        // 当前歌曲封面图片 URL（coverUrl 优先，其次服务器 coverArt；本地 file:// 也可）
        String? coverUrl;
        if (song != null) {
          if ((song.coverUrl ?? '').isNotEmpty) {
            coverUrl = song.coverUrl;
          } else if (song.coverArt != null && song.coverArt!.isNotEmpty) {
            coverUrl = controller.client
                ?.coverUrl(song.coverArt, size: 600)
                ?.toString();
          }
        }
        // 无当前播放封面时，用页面传入的兜底封面（列表首曲等），保证封面透出背景始终有内容
        coverUrl ??= fallbackCoverUrl;
        final useCover = isCover && (coverUrl != null && coverUrl.isNotEmpty);
        return Stack(
          fit: StackFit.expand,
          children: [
            if (useCover)
              // 开启「当前歌曲封面」：主体仍为系统浅色/深色或自定义背景色，
              // 上方只叠加一层很淡的模糊封面，随切歌自动更新。
              // 兜底：底层先铺页面入口封面（歌单/榜单/电台封面），上层再铺当前歌曲封面，
              // 两层封面加载中/失败均显示为**透明**（不是不透明底色块），
              // 失败时自然露出下一层：当前封面失败→露入口封面，入口封面也失败→露 plainBg 染色底，
              // 任何状态下背景都不会被不透明占位块盖成纯白。
              Positioned.fill(
                child: ColoredBox(
                  color: plainBg,
                  child: Opacity(
                    opacity: 0.38,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (fallbackCoverUrl != null && fallbackCoverUrl!.isNotEmpty)
                            _coverImage(fallbackCoverUrl!, cs),
                          _coverImage(coverUrl!, cs),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              // 未开启封面：保持原有自定义色或系统主题表面底
              ColoredBox(
                color: plainBg,
              ),
            // 仅未开启封面时可选叠加自定义颜色（开启封面后不加任何颜色）
            if (!useCover && customBg != null)
              Positioned.fill(child: ColoredBox(color: customBg)),
          ],
        );
      },
    );
  }


  Widget _coverImage(String url, ColorScheme cs) {
    // 加载中/失败/非法URL 一律渲染为透明（SizedBox.shrink），
    // 让底层 fallback 封面或 plainBg 染色底透出；不能铺不透明占位色块，
    // 否则会盖住下层封面，背景整块变浅白。
    final transparent = const SizedBox.shrink();
    final uri = Uri.tryParse(url);
    if (uri == null) return transparent;
    if (uri.scheme == 'file') {
      return Image.file(
        File(uri.toFilePath()),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => transparent,
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      httpHeaders: _imgHeaders(url),
      fadeInDuration: const Duration(milliseconds: 300),
      fadeOutDuration: const Duration(milliseconds: 200),
      placeholder: (_, __) => transparent,
      errorWidget: (_, __, ___) => transparent,
    );
  }
}


/// 页面级背景封装：给 push 出来的独立路由（搜索/歌单/专辑/歌手等）铺上
/// 封面玻璃背景，避免透明 Scaffold 透出黑色路由底层。
class PageBackground extends StatelessWidget {
  const PageBackground({
    super.key,
    required this.controller,
    required this.settings,
    required this.child,
    this.fallbackCoverUrl,
  });
  final PlayerController controller;
  final AppSettings settings;
  final Widget child;
  final String? fallbackCoverUrl;
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: CoverGlassBackground(controller: controller, settings: settings, fallbackCoverUrl: fallbackCoverUrl),
        ),
        Positioned.fill(child: child),
      ],
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
