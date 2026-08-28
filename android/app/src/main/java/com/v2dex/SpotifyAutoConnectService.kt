package com.v2dex

import android.app.AppOpsManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.Process
import android.provider.Settings
import android.util.Log
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

const val ACTION_START_SPOTIFY_MONITOR = "com.v2dex.START_SPOTIFY_MONITOR"
const val ACTION_STOP_SPOTIFY_MONITOR = "com.v2dex.STOP_SPOTIFY_MONITOR"
const val SPOTIFY_PACKAGE_NAME = "com.spotify.music"

class SpotifyAutoConnectService : Service() {
  @Volatile private var running = false
  private val worker =
      Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "v2dex-spotify-monitor")
      }

  override fun onCreate() {
    super.onCreate()
    activeService = this
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
      ACTION_STOP_SPOTIFY_MONITOR -> {
        stopMonitor()
        return START_NOT_STICKY
      }
      ACTION_START_SPOTIFY_MONITOR, null -> startMonitor()
    }

    return START_STICKY
  }

  override fun onDestroy() {
    running = false
    worker.shutdownNow()
    if (activeService === this) {
      activeService = null
    }
    super.onDestroy()
  }

  override fun onBind(intent: Intent?): IBinder? = null

  private fun startMonitor() {
    startForeground(NOTIFICATION_ID, buildNotification())
    if (running) {
      return
    }

    running = true
    worker.execute { monitorLoop() }
  }

  private fun stopMonitor() {
    prefs().edit().putBoolean(PREF_ENABLED, false).apply()
    running = false
    stopForegroundCompat()
    stopSelf()
  }

  private fun monitorLoop() {
    while (running && prefs().getBoolean(PREF_ENABLED, false)) {
      try {
        if (!hasUsageStatsPermission(this)) {
          Log.w(TAG, "Usage access missing; stopping Spotify monitor.")
          stopMonitor()
          return
        }

        if (foregroundPackageName() in SPOTIFY_PACKAGE_NAMES && shouldStartVpn()) {
          startSavedVpn()
          TimeUnit.SECONDS.sleep(10)
        } else {
          TimeUnit.MILLISECONDS.sleep(POLL_INTERVAL_MS)
        }
      } catch (interrupted: InterruptedException) {
        Thread.currentThread().interrupt()
        return
      } catch (error: Throwable) {
        Log.w(TAG, "Spotify monitor loop failed", error)
        try {
          TimeUnit.SECONDS.sleep(3)
        } catch (_: InterruptedException) {
          Thread.currentThread().interrupt()
          return
        }
      }
    }

    stopForegroundCompat()
    stopSelf()
  }

  private fun shouldStartVpn(): Boolean =
      !V2DexVpnService.status.connected &&
          !V2DexVpnService.status.connecting &&
          VpnService.prepare(this) == null &&
          !prefs().getString(PREF_CONFIG_JSON, null).isNullOrBlank()

  private fun startSavedVpn() {
    val prefs = prefs()
    val configJson = prefs.getString(PREF_CONFIG_JSON, null) ?: return
    val mode = prefs.getString(PREF_MODE, "full") ?: "full"
    val appRulesJson = prefs.getString(PREF_APP_RULES_JSON, "[]") ?: "[]"

    Log.d(TAG, "Spotify is foreground; starting VPN.")
    val intent =
        Intent(this, V2DexVpnService::class.java)
            .setAction(ACTION_START)
            .putExtra(EXTRA_CONFIG_JSON, configJson)
            .putExtra(EXTRA_MODE, mode)
            .putExtra(EXTRA_APP_RULES_JSON, appRulesJson)

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      startForegroundService(intent)
    } else {
      startService(intent)
    }
  }

  private fun foregroundPackageName(): String? {
    val manager = getSystemService(UsageStatsManager::class.java) ?: return null
    val now = System.currentTimeMillis()
    val events = manager.queryEvents(now - FOREGROUND_LOOKBACK_MS, now)
    val event = UsageEvents.Event()
    var foregroundPackage: String? = null

    while (events.hasNextEvent()) {
      events.getNextEvent(event)
      if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND ||
          (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
              event.eventType == UsageEvents.Event.ACTIVITY_RESUMED)) {
        foregroundPackage = event.packageName
      }
    }

    return foregroundPackage
  }

  private fun buildNotification(): Notification {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val manager = getSystemService(NotificationManager::class.java)
      manager.createNotificationChannel(
          NotificationChannel(
              NOTIFICATION_CHANNEL_ID,
              "V2DEX Spotify monitor",
              NotificationManager.IMPORTANCE_LOW))
    }

    val settingsIntent =
        Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    val pendingFlags =
        PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
    val pendingIntent =
        PendingIntent.getActivity(
            this,
            0,
            settingsIntent,
            pendingFlags)

    val builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
          @Suppress("DEPRECATION")
          Notification.Builder(this)
        }

    return builder
        .setSmallIcon(R.mipmap.ic_launcher)
        .setContentTitle("V2DEX")
        .setContentText("Watching Spotify for auto-connect")
        .setOngoing(true)
        .setContentIntent(pendingIntent)
        .setCategory(Notification.CATEGORY_SERVICE)
        .build()
  }

  private fun stopForegroundCompat() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      stopForeground(STOP_FOREGROUND_REMOVE)
    } else {
      @Suppress("DEPRECATION")
      stopForeground(true)
    }
  }

  private fun prefs() = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

  companion object {
    private const val TAG = "V2DexSpotifyMonitor"
    private const val PREFS_NAME = "v2dex_spotify_auto_connect"
    private const val PREF_ENABLED = "enabled"
    private const val PREF_CONFIG_JSON = "configJson"
    private const val PREF_MODE = "mode"
    private const val PREF_APP_RULES_JSON = "appRulesJson"
    private const val NOTIFICATION_CHANNEL_ID = "v2dex_spotify_monitor"
    private const val NOTIFICATION_ID = 43081
    private const val POLL_INTERVAL_MS = 1500L
    private const val FOREGROUND_LOOKBACK_MS = 10_000L
    private val SPOTIFY_PACKAGE_NAMES = setOf(SPOTIFY_PACKAGE_NAME, "com.spotify.lite")
    @Volatile private var activeService: SpotifyAutoConnectService? = null

    fun setEnabled(
        context: Context,
        enabled: Boolean,
        configJson: String,
        mode: String,
        appRulesJson: String
    ) {
      val appContext = context.applicationContext
      val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
      if (enabled) {
        prefs
            .edit()
            .putBoolean(PREF_ENABLED, true)
            .putString(PREF_CONFIG_JSON, configJson)
            .putString(PREF_MODE, mode)
            .putString(PREF_APP_RULES_JSON, appRulesJson)
            .apply()
        val intent = Intent(appContext, SpotifyAutoConnectService::class.java).setAction(ACTION_START_SPOTIFY_MONITOR)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          appContext.startForegroundService(intent)
        } else {
          appContext.startService(intent)
        }
      } else {
        prefs.edit().putBoolean(PREF_ENABLED, false).apply()
        val intent = Intent(appContext, SpotifyAutoConnectService::class.java).setAction(ACTION_STOP_SPOTIFY_MONITOR)
        appContext.startService(intent)
        activeService?.stopMonitor()
      }
    }

    fun isEnabled(context: Context): Boolean =
        context
            .applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(PREF_ENABLED, false)

    fun hasUsageStatsPermission(context: Context): Boolean {
      val appOps = context.getSystemService(AppOpsManager::class.java) ?: return false
      val mode =
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName)
          } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName)
          }
      return mode == AppOpsManager.MODE_ALLOWED
    }
  }
}
