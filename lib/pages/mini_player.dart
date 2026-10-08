import 'package:flutter/material.dart';

import '../player_controller.dart';
import '../settings.dart';
import '../widgets.dart';
import 'player_page.dart';

/// 杩蜂綘鎾斁鏍忥細瀹屽叏閫忔槑锛堣儗鏅€忓嚭澶栧眰 PageBackground/CoverGlassBackground锛夛紝
/// 涓庨椤?闊充箰搴?瀵艰埅鏍忕粺涓€鐢辫缃殑涓婚寮€鍏虫帶鍒讹紱鍐呭璺熼殢涓婚鑹层€?/// 杞︽満妯睆锛坙andscape锛夋椂鏁翠綋鍘嬬缉灏哄锛岄伩鍏嶅崰妯悜绌洪棿銆?class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.settings, required this.controller});

  final AppSettings settings;
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final song = controller.current;
        final cs = Theme.of(context).colorScheme;

        // 妯珫灞忛兘鍔犲鍔犻珮銆佸瓧浣撳姞澶?        final mq = MediaQuery.of(context);
        final isLandscape = mq.size.width > mq.size.height;
        final isCarScreen = mq.size.shortestSide >= 480;
        // 杞︽満妯睆搴曢儴鎶珮鐢?home_shell 缁熶竴鎺у埗锛堥伩鍏嶄笌瀵艰埅鏍弍adding鍙犲姞锛?        final bottomPad = isLandscape
            ? (isCarScreen ? 0.0 : 4.0)
            : 48.0;
        final coverSize = isLandscape ? 54.0 : 56.0;
        final hPad = isLandscape ? 20.0 : 16.0;
        final vPad = isLandscape ? 10.0 : 12.0;
        final gap = isLandscape ? 16.0 : 16.0;
        final iconSize = isLandscape ? 30.0 : 32.0;
        final titleSize = isLandscape ? 18.0 : 18.0;
        final artistSize = isLandscape ? 14.0 : 14.0;

        return Container(
          // 浠呬竴鏉¤窡闅忎富棰樼殑缁嗗垎闅旂嚎锛涗笉鐢昏儗鏅壊鈥斺€旈€忓嚭 PageBackground锛屼笌鍏ㄥ眬涓婚缁熶竴
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.25),
                width: 0.5,
              ),
            ),
          ),
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  PlayerPage(settings: settings, controller: controller),
            )),
            child: Padding(
              // 杞︽満妯睆鐩存帴鐢ㄥ浐瀹氭姮楂樺€硷紱鎵嬫満鐢ㄧ郴缁熸墜鍔挎潯 padding
              padding: EdgeInsets.only(
                bottom: isLandscape && isCarScreen
                    ? bottomPad
                    : mq.padding.bottom.clamp(0.0, bottomPad),
              ),
              child: Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
                child: song == null
                    // 甯搁┗搴曟爮锛氭湭鎾斁鏃舵樉绀哄崰浣嶏紙闊崇 + 鏈湪鎾斁锛?                    ? Row(
                        children: [
                          Container(
                            width: coverSize,
                            height: coverSize,
                            decoration: BoxDecoration(
                              color: cs.onSurface.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.music_note_rounded,
                                color: cs.onSurfaceVariant, size: iconSize),
                          ),
                          SizedBox(width: gap),
                          Expanded(
                            child: Text('鏈湪鎾斁',
                                style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontSize: titleSize)),
                          ),
                          Icon(Icons.play_circle_outline_rounded,
                              color: cs.onSurfaceVariant, size: iconSize),
                          SizedBox(width: gap),
                        ],
                      )
                    : Row(
                        children: [
                          CoverImage(
                            client: controller.client,
                            coverId: song.coverArt,
                            coverUrl: song.coverUrl,
                            size: coverSize,
                            radius: 8,
                            requestSize: 120,
                          ),
                          SizedBox(width: gap),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: cs.onSurface,
                                        fontWeight: FontWeight.w600,
                                        fontSize: titleSize)),
                                Text(song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                        fontSize: artistSize)),
                              ],
                            ),
                          ),
                          IconButton(
                            iconSize: iconSize,
                            icon: Icon(
                                controller.playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: cs.onSurface),
                            onPressed: controller.togglePlay,
                          ),
                          IconButton(
                            iconSize: iconSize,
                            icon: Icon(Icons.skip_next_rounded,
                                color: cs.onSurface),
                            onPressed:
                                controller.hasNext ? controller.next : null,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
