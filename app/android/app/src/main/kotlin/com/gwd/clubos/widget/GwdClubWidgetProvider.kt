package com.gwd.clubos.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import com.gwd.clubos.R
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * The Android home-screen widget (Section 7).
 *
 * Flutter cannot draw launcher widgets itself, so the app writes a small
 * snapshot through the `home_widget` plugin and this provider renders it with
 * RemoteViews. Android allows frequent widget updates, so this tracks the app
 * closely — unlike iOS, where WidgetKit's timeline budget means the same data
 * may be up to 15–30 minutes stale.
 *
 * Everything here is read-only and defensive: the widget must render something
 * sensible even before the app has ever run and written any data.
 */
class GwdClubWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val prefs = HomeWidgetPlugin.getData(context)

        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.gwd_club_widget).apply {
                render(this, prefs)
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun render(views: RemoteViews, prefs: SharedPreferences) {
        val pending = prefs.getInt("pendingCount", 0)
        val nextTitle = prefs.getString("nextTitle", "").orEmpty()
        val nextDue = prefs.getString("nextDue", "").orEmpty()

        views.setTextViewText(R.id.widget_count, pending.toString())
        views.setTextViewText(
            R.id.widget_count_label,
            if (pending == 1) "task pending" else "tasks pending",
        )

        // The second line is the genuinely useful part — what is next and when.
        val detail = when {
            nextTitle.isBlank() -> "Nothing due. You're clear."
            nextDue.isBlank() -> nextTitle
            else -> "$nextTitle · ${nextDue.removePrefix("Due ")}"
        }
        views.setTextViewText(R.id.widget_next, detail)
    }
}
