# 音素 xMusic

一款开源的 Flutter 音乐播放器，支持 Navidrome/Subsonic 自建音乐服务器，同时聚合网易云、B站等外网音源。

## 功能

### 本地音乐（Navidrome/Subsonic）
- 浏览歌曲、专辑、歌手、歌单
- 播放队列管理
- 收藏/下载到本地或NAS WebDAV
- 歌词同步显示（双击刷新）
- 播放模式：顺序/随机/单曲循环

### 在线音源
- **网易云**：直连API，排行榜、歌单、搜索、播放、封面、歌词
- **B站**：搜索、播放
- **GDStudio API**：多源搜索聚合（QQ/网易/酷狗/酷我/B站）
- 首页排行榜：飙升榜、新歌榜、原创榜、热歌榜等12个榜单

### 播放界面
- 竖屏：黑胶封面 + 歌词 + 进度条 + 控制栏
- 横屏（车机）：左大黑胶 + 右歌词5行靠右
- 通知栏媒体控制（Android MediaSession）
- 车机识别（APP_MUSIC category）

### 个性化
- 主题模式：浅色/深色/跟随系统
- 自定义主题色（低饱和预设 + HSV选色器 + 16进制输入）
- 歌词颜色自定义（当前/已唱/未唱分别配色）
- 玻璃通透度调节（0%-100%，最低全透明）
- 歌词字号调节

### 其他
- 封面缓存（CachedNetworkImage）
- 启动自动播放开关
- 本地下载路径设置
- 本地歌单随机播放

## 技术栈

- Flutter + Dart
- just_audio（音频播放）
- audio_service（后台播放 + 通知栏控制）
- cached_network_image（封面缓存）
- scrollable_positioned_list（歌词滚动）
- 直连网易云API + GDStudio聚合API

## 构建

通过 GitHub Actions 自动构建APK：
- 推送 main 分支自动触发
- 版本号：0.3.X（X = workflow run number）
- 产物：`my-player-apk` artifact

## 下载

前往 [Actions](https://github.com/xch1986/xmusic/actions) 下载最新构建的APK。

## 配置

首次启动需在设置中配置：
1. **源** → Navidrome 服务器地址、用户名、密码
2. **源** → 外部API地址（默认 gdStudio）
3. **主题** → 选择主题模式和颜色
4. **歌词** → 歌词字号、颜色

## License

MIT
