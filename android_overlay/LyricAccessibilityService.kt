package __PKG__

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent

class LyricAccessibilityService : AccessibilityService() {
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED ||
            event?.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            event.packageName?.let {
                LyricOverlayService.accessibilityForeground = it.toString()
            }
        }
    }

    override fun onInterrupt() {}

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        LyricOverlayService.accessibilityForeground = null
        return super.onUnbind(intent)
    }
}
