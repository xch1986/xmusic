package __PKG__

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 1) 显式拉起音频服务：App 启动（前台）即启动 AudioService，
        //    未播放也持有 MediaSession，车机（迪友）桌面才能枚举到音素。
        try {
            startService(Intent(this, Class.forName("com.ryanheise.audioservice.AudioService")))
        } catch (_: Throwable) {}
        // 2) 激活 MediaSession（setActive(true)）：audio_service 只在真正播放
        //    （enterPlayingState）时才激活会话，未播放/暂停时迪友 getActiveSessions
        //    枚举不到 → 小窗绑定不到、桌面卡片不同步、方向盘键无目标。
        //    这里在服务启动后反射激活一次（暂停不会失活；stop/销毁后服务重建时本方法再执行）。
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                val svc = Class.forName("com.ryanheise.audioservice.AudioService")
                val instField = svc.getDeclaredField("instance")
                instField.isAccessible = true
                val inst = instField.get(null)
                if (inst != null) {
                    val f = svc.getDeclaredField("mediaSession")
                    f.isAccessible = true
                    val ms = f.get(inst)
                    val m = ms.javaClass.getMethod("setActive", Boolean::class.javaPrimitiveType)
                    m.invoke(ms, true)
                }
            } catch (_: Throwable) {}
        }, 3000)
    }
}
