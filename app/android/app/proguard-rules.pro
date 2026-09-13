# Keep rules.
#
# Minification is currently DISABLED in build.gradle.kts (see the comment
# there). These rules exist so that turning it back on is survivable rather
# than a fresh round of release-only crashes.
#
# The crash they prevent, for the record:
#   java.lang.RuntimeException: Unable to get provider
#   androidx.startup.InitializationProvider:
#     Failed to create an instance of androidx.work.impl.WorkDatabase
#
# Cause: Room builds its database by reflectively loading a generated class
# named "<DatabaseClass>_Impl". R8 renames that class, the lookup fails, and
# because WorkManager initialises through androidx.startup — which runs before
# any Activity — the process dies before drawing a frame.

# ---------------------------------------------------------------------------
# Room — generated *_Impl classes are resolved by name at runtime.
# ---------------------------------------------------------------------------
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep @androidx.room.Database class * { *; }
-dontwarn androidx.room.paging.**

# ---------------------------------------------------------------------------
# WorkManager — instantiated reflectively, and initialised via androidx.startup.
# ---------------------------------------------------------------------------
-keep class androidx.work.impl.WorkDatabase { *; }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.work.Worker { *; }
-keep class * extends androidx.work.ListenableWorker { <init>(...); }
-keep class androidx.work.WorkManagerInitializer { *; }
-keep class androidx.work.impl.** { *; }

# androidx.startup providers are named in the manifest and loaded by name.
-keep class androidx.startup.** { *; }
-keep class * implements androidx.startup.Initializer { *; }

# ---------------------------------------------------------------------------
# home_widget — the widget provider is resolved from the manifest by name.
# ---------------------------------------------------------------------------
-keep class es.antonborri.home_widget.** { *; }
-keep class com.gwd.clubos.widget.** { *; }

# Glance / Compose runtime, pulled in by home_widget.
-keep class androidx.glance.** { *; }
-dontwarn androidx.glance.**

# ---------------------------------------------------------------------------
# Optional Firebase path — only present once the club supplies
# google-services.json.
# ---------------------------------------------------------------------------
-dontwarn com.google.firebase.**
-dontwarn io.flutter.plugins.firebase.**
