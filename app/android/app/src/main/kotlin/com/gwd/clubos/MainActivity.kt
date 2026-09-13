package com.gwd.clubos

import android.os.Build
import android.os.Bundle
import android.view.Display
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighestRefreshRate()
    }

    /**
     * Ask the display for its fastest mode.
     *
     * Flutter renders at whatever rate the window is running at, and on a great
     * many Android phones — OnePlus and Samsung especially — a window sits at
     * 60Hz until the app explicitly asks for more, even on a 120Hz panel. The
     * app then looks obviously less fluid than the launcher it was opened from,
     * which reads as the app being slow rather than the window being throttled.
     *
     * Two details matter:
     *
     *  - **Only consider modes at the current resolution.** Some devices expose
     *    a fast mode that is also a lower resolution; blindly taking the highest
     *    refresh rate would quietly downgrade the display to buy smoothness
     *    nobody asked to trade for.
     *  - **This is a request, not a command.** The system overrides it under
     *    battery saver, in low light, or on its own thermal judgement, which is
     *    correct — a club app should not be the reason somebody's phone runs
     *    hot. Nothing here fails if it is refused.
     */
    private fun requestHighestRefreshRate() {
        // supportedModes arrived in API 23.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return

        val display: Display? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            }
        if (display == null) return

        val current = display.mode ?: return
        val fastest = display.supportedModes
            // Same pixels, more frames — never fewer pixels for more frames.
            ?.filter {
                it.physicalWidth == current.physicalWidth &&
                    it.physicalHeight == current.physicalHeight
            }
            ?.maxByOrNull { it.refreshRate }
            ?: return

        // Already on the best mode; touching window attributes would be churn.
        if (fastest.modeId == current.modeId) return

        window.attributes = window.attributes.apply {
            preferredDisplayModeId = fastest.modeId
        }
    }
}
