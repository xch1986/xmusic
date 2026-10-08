package __PKG__

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.text.SpannableString
import android.text.Spanned
import android.text.TextUtils
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

class LyricOverlayService : Service() {
    companion object {
        const val ACTION_START = "cn.yinsu.x_music.OVERLAY_START"
        const val ACTION_STOP = "cn.yinsu.x_music.OVERLAY_STOP"
        const val ACTION_UPDATE = "cn.yinsu.x_music.OVERLAY_UPDATE"
        const val EXTRA_LYRIC = "lyric"
        const val EXTRA_TITLE = "title"
        const val EXTRA_ARTIST = "artist"
        const val EXTRA_COVER = "cover"
        const val EXTRA_LINE = "line"
        @Volatile var accessibilityForeground: String? = null
        private const val CHANNEL_ID = "xmusic_lyric_overlay"
    }

    private var wm: WindowManager? = null
    private var root: View? = null
    private var vinylView: View? = null
    private var titleView: TextView? = null
    private var artistView: TextView? = null
    private var lyricView: TextView? = null
    private var added = false
    private var _lyric: String = ""
    private var title: String = ""
    private var artist: String = ""
    private var cover: String = ""
    private var line = 0
    private val handler = Handler(Looper.getMainLooper())
    private var loopTask: Runnable? = null
    private var wmParams: WindowManager.LayoutParams? = null
    private var sizeSp = 15f
    private var minusBtn: TextView? = null
    private var plusBtn: TextView? = null
    private var startRawX = 0f
    private var startRawY = 0f
    private var dragDx = 0f
    private var dragDy = 0f
    private var moved = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startForegroundCompat()
        wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_UPDATE -> {
                val text = intent.getStringExtra(EXTRA_LYRIC) ?: ""
                if (text.isNotEmpty()) {
                    _lyric = text
                    title = intent.getStringExtra(EXTRA_TITLE) ?: ""
                    artist = intent.getStringExtra(EXTRA_ARTIST) ?: ""
                    cover = intent.getStringExtra(EXTRA_COVER) ?: ""
                    line = intent.getIntExtra(EXTRA_LINE, 0)
                    titleView?.text = title
                    artistView?.text = artist
                    applyLyricSize()
                    vinylView?.let { (it as VinylView).startSpin() }
                }
            }
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
        }
        startLoop()
        return START_STICKY
    }

    private fun startForegroundCompat() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "歌词悬浮窗", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val pi = PendingIntent.getActivity(
            this, 0, packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE
        )
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        val notif = b.setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("音素音乐")
            .setContentText("歌词悬浮窗运行中")
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(1, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(1, notif)
        }
    }

    private fun startLoop() {
        loopTask?.let { handler.removeCallbacks(it) }
        loopTask = Runnable {
            updateVisibility()
            handler.postDelayed(loopTask!!, 1000)
        }
        handler.post(loopTask!!)
    }

    private fun launcherPackage(): String? {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val ri = packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
        return ri?.activityInfo?.packageName
    }

    private fun topPackage(): String? {
        // 无障碍实时前台优先；否则 UsageStats 兜底
        accessibilityForeground?.let { if (it.isNotEmpty()) return it }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                val end = System.currentTimeMillis()
                val events = usm.queryEvents(end - 3000, end)
                var top: String? = null
                while (events.hasNextEvent()) {
                    val e = UsageEvents.Event()
                    events.getNextEvent(e)
                    if (e.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) top = e.packageName
                }
                return top
            } catch (_: Exception) {}
        }
        return null
    }

    /** 车机/大屏判定：最短边 >=480dp 视为车机大屏（车机拿不到前台权限，主界面即桌面）。 */
    private fun isCarScreen(): Boolean {
        return try {
            val dm = resources.displayMetrics
            val s = kotlin.math.min(dm.widthPixels, dm.heightPixels) / dm.density
            s >= 480
        } catch (_: Exception) { false }
    }

    private fun updateVisibility() {
        val launcher = launcherPackage()
        val top = topPackage()
        // 只在迪友桌面（com.dy.launcher，比亚迪车机桌面）前台时才显示；设置页/小窗/其它 app 一律不浮。
        // 前台识别依赖无障碍/UsageStats 授权；未授权无法判断前台则一律不显示。
        val show = _lyric.isNotEmpty() && top == "com.dy.launcher"
        if (show && !added) addView()
        else if (!show && added) removeView()
    }

    /** 竖屏播放界面样式：旋转黑胶 + 歌名/歌手 + 歌词4行（可拖动、字号可调）。 */
    private fun addView() {
        if (added) return
        val d = resources.displayMetrics.density
        val w = (300 * d).toInt()
        val lp = WindowManager.LayoutParams(
            w,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        )
        lp.gravity = Gravity.TOP or Gravity.START
        val sw = resources.displayMetrics.widthPixels
        lp.x = ((sw - w) / 2)
        lp.y = (d * 60).toInt()
        wmParams = lp

        // 根容器：圆角半透明玻璃
        val rootV = FrameLayout(this)
        val bg = GradientDrawable()
        bg.cornerRadius = (20 * d)
        bg.setColor(0xB0121212.toInt())
        rootV.background = bg

        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL
        col.gravity = Gravity.CENTER_HORIZONTAL
        col.setPadding((18 * d).toInt(), (14 * d).toInt(), (18 * d).toInt(), (14 * d).toInt())
        col.layoutParams = FrameLayout.LayoutParams(w, FrameLayout.LayoutParams.WRAP_CONTENT)

        // 旋转黑胶
        val vinyl = VinylView(this)
        vinyl.layoutParams = LinearLayout.LayoutParams((140 * d).toInt(), (140 * d).toInt())
        vinyl.startSpin()

        // 歌名
        val tvTitle = TextView(this)
        tvTitle.text = title
        tvTitle.setTextColor(0xFFFFFFFF.toInt())
        tvTitle.setTextSize(18f)
        tvTitle.typeface = Typeface.DEFAULT_BOLD
        tvTitle.gravity = Gravity.CENTER
        tvTitle.setSingleLine(true)
        tvTitle.ellipsize = TextUtils.TruncateAt.END

        // 歌手
        val tvArtist = TextView(this)
        tvArtist.text = artist
        tvArtist.setTextColor(0xB3FFFFFF.toInt())
        tvArtist.setTextSize(13f)
        tvArtist.gravity = Gravity.CENTER

        // 歌词 4 行（当前行居中高亮）
        val tvLyric = TextView(this)
        tvLyric.setTextSize(sizeSp)
        tvLyric.gravity = Gravity.CENTER
        tvLyric.setLineSpacing(0f, 1.25f)
        tvLyric.text = buildLyricWindow(_lyric, line, sizeSp)

        // 字号调节按钮（− / +）
        val sizeRow = LinearLayout(this)
        sizeRow.orientation = LinearLayout.HORIZONTAL
        sizeRow.gravity = Gravity.CENTER_HORIZONTAL
        val minus = smallTextBtn("−", d)
        val plus = smallTextBtn("+", d)
        sizeRow.addView(minus)
        sizeRow.addView(plus)
        minusBtn = minus
        plusBtn = plus

        col.addView(vinyl)
        col.addView(tvTitle)
        col.addView(tvArtist)
        col.addView(tvLyric)
        col.addView(sizeRow)
        rootV.addView(col)

        vinylView = vinyl
        titleView = tvTitle
        artistView = tvArtist
        lyricView = tvLyric
        root = rootV
        try {
            wm?.addView(rootV, lp)
            added = true
            rootV.setOnTouchListener(overlayTouchListener)
        } catch (_: Exception) {
            added = false
        }
    }

    /** 构建歌词窗口：取当前行居中的 4 行，当前行白色加粗放大，其他行半透明白。 */
    private fun buildLyricWindow(full: String, curLine: Int, sizeSp: Float): CharSequence {
        if (full.isEmpty()) return ""
        val all = full.split("\n")
        val total = all.size
        val start = (curLine - 1).coerceIn(0, (total - 4).coerceAtLeast(0))
        val end = (start + 4).coerceAtMost(total)
        val slice = all.subList(start, end)
        val relCur = (curLine - start).coerceIn(0, 3)
        val sb = StringBuilder()
        for (i in slice.indices) { if (i > 0) sb.append('\n'); sb.append(slice[i]) }
        val sp = SpannableString(sb.toString())
        var pos = 0
        for (i in slice.indices) {
            val len = slice[i].length
            if (i == relCur) {
                sp.setSpan(StyleSpan(Typeface.BOLD), pos, pos + len, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                sp.setSpan(ForegroundColorSpan(0xFFFFFFFF.toInt()), pos, pos + len, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                sp.setSpan(RelativeSizeSpan(1.15f), pos, pos + len, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            } else {
                sp.setSpan(ForegroundColorSpan(0x8CFFFFFF.toInt()), pos, pos + len, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            pos += len + 1
        }
        return sp
    }

    /** 应用字号并刷新歌词 4 行。 */
    private fun applyLyricSize() {
        lyricView?.let { it.setTextSize(sizeSp); it.text = buildLyricWindow(_lyric, line, sizeSp) }
    }

    /** 字号调节小按钮。 */
    private fun smallTextBtn(text: String, d: Float): TextView {
        val tv = TextView(this)
        tv.text = text
        tv.setTextSize(18f)
        tv.setTextColor(0xFFFFFFFF.toInt())
        tv.gravity = Gravity.CENTER
        tv.setPadding((14 * d).toInt(), 0, (14 * d).toInt(), 0)
        tv.setBackgroundColor(0x22FFFFFF.toInt())
        return tv
    }

    /** 点击检测：未拖动时，点到字号按钮则调节。 */
    private fun checkButtonTap(rawX: Float, rawY: Float) {
        minusBtn?.let { b ->
            val loc = IntArray(2); b.getLocationOnScreen(loc)
            if (rawX >= loc[0] && rawX <= loc[0] + b.width && rawY >= loc[1] && rawY <= loc[1] + b.height) {
                sizeSp = (sizeSp - 1f).coerceAtLeast(11f); applyLyricSize(); return
            }
        }
        plusBtn?.let { b ->
            val loc = IntArray(2); b.getLocationOnScreen(loc)
            if (rawX >= loc[0] && rawX <= loc[0] + b.width && rawY >= loc[1] && rawY <= loc[1] + b.height) {
                sizeSp = (sizeSp + 1f).coerceAtMost(28f); applyLyricSize(); return
            }
        }
    }

    /** 窗口拖动 + 点击判断。 */
    private val overlayTouchListener = View.OnTouchListener { v, e ->
        when (e.action) {
            MotionEvent.ACTION_DOWN -> {
                startRawX = e.rawX; startRawY = e.rawY
                val lp = wmParams ?: return@OnTouchListener false
                dragDx = startRawX - lp.x; dragDy = startRawY - lp.y
                moved = false
                true
            }
            MotionEvent.ACTION_MOVE -> {
                val th = (resources.displayMetrics.density * 6).toInt().toFloat()
                if (kotlin.math.abs(e.rawX - startRawX) > th || kotlin.math.abs(e.rawY - startRawY) > th) {
                    val lp = wmParams ?: return@OnTouchListener true
                    lp.x = (e.rawX - dragDx).toInt(); lp.y = (e.rawY - dragDy).toInt()
                    wm?.updateViewLayout(v, lp); moved = true
                }
                true
            }
            MotionEvent.ACTION_UP -> {
                if (!moved) checkButtonTap(e.rawX, e.rawY)
                true
            }
            else -> false
        }
    }

    /** 黑胶唱片视图：同心圆纹路 + 中心标签 + 中心孔，持续旋转。 */
    private inner class VinylView(context: Context) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val spin = ObjectAnimator.ofFloat(this, "rotation", 0f, 360f).apply {
            duration = 8000
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
        }

        fun startSpin() { if (!spin.isStarted) spin.start() }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val cx = width / 2f
            val cy = height / 2f
            val r = kotlin.math.min(width, height) / 2f
            // 唱片主体
            paint.color = 0xFF0D0D0D.toInt()
            paint.style = Paint.Style.FILL
            canvas.drawCircle(cx, cy, r, paint)
            // 同心圆纹路
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 1.2f
            var i = 1
            while (i <= 6) {
                paint.color = 0x1F000000.toInt()
                canvas.drawCircle(cx, cy, r * i / 6f, paint)
                i++
            }
            paint.style = Paint.Style.FILL
            // 中心标签
            paint.color = 0xFF0B3D0B.toInt()
            canvas.drawCircle(cx, cy, r * 0.30f, paint)
            paint.color = 0xFF2E7D32.toInt()
            canvas.drawCircle(cx, cy, r * 0.24f, paint)
            // 中心孔
            paint.color = 0xFF000000.toInt()
            canvas.drawCircle(cx, cy, r * 0.06f, paint)
        }
    }

    private fun removeView() {
        root?.let { v ->
            try { wm?.removeView(v) } catch (_: Exception) {}
        }
        root = null
        vinylView = null
        titleView = null
        artistView = null
        lyricView = null
        added = false
    }

    override fun onDestroy() {
        loopTask?.let { handler.removeCallbacks(it) }
        removeView()
        wm = null
        super.onDestroy()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (added) {
            removeView()
            addView()
        }
    }
}
