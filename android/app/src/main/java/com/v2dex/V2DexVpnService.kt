package com.v2dex

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import hev.htproxy.TProxyService
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.zip.ZipFile
import org.json.JSONArray

const val ACTION_START = "com.v2dex.START_VPN"
const val ACTION_STOP = "com.v2dex.STOP_VPN"
const val EXTRA_CONFIG_JSON = "configJson"
const val EXTRA_MODE = "mode"
const val EXTRA_APP_RULES_JSON = "appRulesJson"

class V2DexVpnService : TProxyService() {
  private var xrayProcess: Process? = null
  private var vpnInterface: ParcelFileDescriptor? = null
  private var tunFd: Int? = null
  private var tun2socksRunning = false
  private val serviceExecutor =
      Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "v2dex-vpn-worker").apply { isDaemon = true }
      }

  override fun onCreate() {
    super.onCreate()
    activeService = this
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
      ACTION_START -> {
        val configJson = intent.getStringExtra(EXTRA_CONFIG_JSON) ?: "{}"
        val mode = intent.getStringExtra(EXTRA_MODE) ?: "full"
        val appRulesJson = intent.getStringExtra(EXTRA_APP_RULES_JSON) ?: "[]"
        status = status.copy(connecting = true, lastError = null, mode = mode, backend = "vpn")
        startForeground(NOTIFICATION_ID, buildNotification("Connecting"))
        serviceExecutor.execute { startXray(configJson, mode, appRulesJson) }
      }
      ACTION_STOP -> requestStopXray()
    }

    return START_NOT_STICKY
  }

  override fun onDestroy() {
    stopTun2socks()
    stopXrayProcess()
    serviceExecutor.shutdownNow()
    if (activeService === this) {
      activeService = null
    }
    super.onDestroy()
  }

  private fun startXray(configJson: String, mode: String, appRulesJson: String) {
    Log.d("V2DexVpnService", "startXray mode=$mode configBytes=${configJson.length}")

    try {
      stopTun2socks()
      stopXrayProcess()

      val runtimeDir = File(filesDir, "xray-runtime").apply { mkdirs() }
      val binary = prepareBundledXrayBinary(runtimeDir)
      extractAsset("xray/geoip.dat", File(runtimeDir, "geoip.dat"))
      extractAsset("xray/geosite.dat", File(runtimeDir, "geosite.dat"))

      val configFile = File(runtimeDir, "config.json")
      configFile.writeText(configJson)

      val process =
          ProcessBuilder(binary.absolutePath, "run", "-config", configFile.absolutePath)
              .directory(runtimeDir)
              .redirectErrorStream(true)
              .apply {
                environment()["XRAY_LOCATION_ASSET"] = runtimeDir.absolutePath
              }
              .start()

      xrayProcess = process
      consumeProcessOutput(process)
      Thread.sleep(450)

      if (!process.isAlive) {
        Log.e("V2DexVpnService", "Xray exited early: ${lastXrayLog ?: "no log"}")
        throw IllegalStateException("Xray exited before opening SOCKS on 0.0.0.0:43080.")
      }

      val tunnelConfig = File(runtimeDir, "tun2socks.yml")
      tunnelConfig.writeText(buildTun2socksConfig())
      val vpn = establishVpn(mode, appRulesJson)
      vpnInterface = vpn
      val detachedTunFd = vpn.detachFd()
      vpnInterface = null
      tunFd = detachedTunFd
      TProxyStartService(tunnelConfig.absolutePath, detachedTunFd)
      tun2socksRunning = true

      status =
          AndroidTunnelStatus(
              connected = true,
              connecting = false,
              mode = mode,
              backend = "vpn",
              lastConnectedAt = isoNow(),
              activeConfigPath = configFile.absolutePath,
              binaryPath = binary.absolutePath)
      startForeground(NOTIFICATION_ID, buildNotification("Connected"))
      Log.d("V2DexVpnService", "VPN + Xray started binary=${binary.absolutePath}")
    } catch (error: Exception) {
      Log.e("V2DexVpnService", "Xray start failed", error)
      stopTun2socks()
      stopXrayProcess()
      status =
          AndroidTunnelStatus(
              connected = false,
              connecting = false,
              mode = mode,
              backend = "vpn",
              lastError = error.message ?: "Xray start failed.")
      stopForegroundCompat()
      stopSelf()
    }
  }

  private fun requestStopXray() {
    status =
        AndroidTunnelStatus(
            connected = false,
            connecting = false,
            mode = status.mode,
            backend = "vpn")
    serviceExecutor.execute { stopXray() }
  }

  private fun stopXray() {
    stopTun2socks()
    stopXrayProcess()
    status =
        AndroidTunnelStatus(
            connected = false,
            connecting = false,
            mode = status.mode,
            backend = "vpn")
    stopForegroundCompat()
    stopSelf()
  }

  private fun buildNotification(state: String): Notification {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val manager = getSystemService(NotificationManager::class.java)
      val channel =
          NotificationChannel(
              NOTIFICATION_CHANNEL_ID,
              "V2DEX tunnel",
              NotificationManager.IMPORTANCE_LOW)
      manager.createNotificationChannel(channel)
    }

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
        .setContentText("Tunnel $state")
        .setOngoing(true)
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

  private fun establishVpn(mode: String, appRulesJson: String): ParcelFileDescriptor {
    val builder =
        Builder()
            .setSession("V2DEX")
            .setMtu(VPN_MTU)
            .addAddress(VPN_IPV4_ADDRESS, 16)
            .addAddress(VPN_IPV6_ADDRESS, 126)
            .addRoute("0.0.0.0", 0)
            .addRoute("::", 0)
            .addDnsServer("1.1.1.1")
            .addDnsServer("8.8.8.8")
            .addDnsServer("2606:4700:4700::1111")
            .addDnsServer("2001:4860:4860::8888")

    if (mode == "per-app") {
      val packages = selectedPackages(appRulesJson)
      if (packages.isEmpty()) {
        throw IllegalStateException("Select at least one app for per-app proxy mode.")
      }

      Log.d("V2DexVpnService", "Per-app allowed packages=${packages.joinToString(",")}")
      packages.forEach { packageName ->
        try {
          builder.addAllowedApplication(packageName)
        } catch (error: Exception) {
          Log.w("V2DexVpnService", "Could not allow app $packageName", error)
        }
      }
    } else {
      try {
        builder.addDisallowedApplication(packageName)
      } catch (error: Exception) {
        Log.w("V2DexVpnService", "Could not exclude V2DEX from VPN", error)
      }
    }

    return builder.establish() ?: throw IllegalStateException("Android VPN interface could not be created.")
  }

  private fun selectedPackages(appRulesJson: String): List<String> {
    val result = mutableListOf<String>()
    val rules = JSONArray(appRulesJson)
    for (index in 0 until rules.length()) {
      val rule = rules.optJSONObject(index) ?: continue
      if (rule.optBoolean("enabled")) {
        val bundleId = rule.optString("bundleId")
        if (bundleId.isNotBlank() && bundleId != packageName) {
          result.add(bundleId)
        }
      }
    }
    return result
  }

  private fun buildTun2socksConfig() =
      """
      tunnel:
        name: tun0
        mtu: $VPN_MTU
        multi-queue: false
        ipv4: $VPN_IPV4_ADDRESS
        ipv6: $VPN_IPV6_ADDRESS

      socks5:
        port: 43080
        address: 127.0.0.1
        udp: 'udp'

      misc:
        connect-timeout: 15000
        tcp-read-write-timeout: 300000
        udp-read-write-timeout: 60000
        log-level: warn
      """
          .trimIndent()

  private fun stopTun2socks() {
    if (tun2socksRunning) {
      try {
        TProxyStopService()
      } catch (error: Exception) {
        Log.w("V2DexVpnService", "tun2socks stop failed", error)
      }
      tun2socksRunning = false
    }

    closeDetachedTunFd()

    try {
      vpnInterface?.close()
    } catch (_: Exception) {}
    vpnInterface = null
  }

  private fun closeDetachedTunFd() {
    val fd = tunFd ?: return
    tunFd = null

    try {
      ParcelFileDescriptor.adoptFd(fd).close()
    } catch (error: Exception) {
      Log.w("V2DexVpnService", "TUN fd close failed", error)
    }
  }

  private fun stopXrayProcess() {
    try {
      xrayProcess?.destroy()
      xrayProcess?.waitFor(1200, TimeUnit.MILLISECONDS)
    } catch (_: Exception) {
      try {
        xrayProcess?.destroyForcibly()
      } catch (_: Exception) {}
    }

    xrayProcess = null
  }

  private fun extractAsset(assetName: String, destination: File): File {
    if (destination.exists() && destination.length() > 0) {
      return destination
    }

    destination.parentFile?.mkdirs()
    assets.open(assetName).use { input ->
      destination.outputStream().use { output ->
        input.copyTo(output)
      }
    }

    return destination
  }

  private fun prepareBundledXrayBinary(runtimeDir: File): File {
    val nativeBinary = File(applicationInfo.nativeLibraryDir, "libxray.so")

    if (nativeBinary.exists() && nativeBinary.length() > 0L) {
      if (!nativeBinary.setExecutable(true, true) && !nativeBinary.canExecute()) {
        throw IllegalStateException("Bundled Xray binary is not executable.")
      }

      return nativeBinary
    }

    val runtimeBinary = File(runtimeDir, "xray")
    extractNativeXrayFromApk(runtimeBinary)

    if (!runtimeBinary.setExecutable(true, true) && !runtimeBinary.canExecute()) {
      throw IllegalStateException("Xray binary could not be marked executable.")
    }

    return runtimeBinary
  }

  private fun extractNativeXrayFromApk(runtimeBinary: File) {
    val apkPath = applicationInfo.sourceDir
    val abi = android.os.Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"
    val entries = listOf("lib/$abi/libxray.so", "lib/arm64-v8a/libxray.so")

    ZipFile(apkPath).use { apk ->
      val entry = entries.firstNotNullOfOrNull { apk.getEntry(it) }
          ?: throw IllegalStateException("Bundled Xray binary was not found in APK.")

      if (runtimeBinary.exists() && runtimeBinary.length() == entry.size) {
        return
      }

      runtimeBinary.parentFile?.mkdirs()
      apk.getInputStream(entry).use { input ->
        runtimeBinary.outputStream().use { output ->
          input.copyTo(output)
        }
      }
    }

    if (!runtimeBinary.exists() || runtimeBinary.length() == 0L) {
      throw IllegalStateException("Bundled Xray binary could not be extracted from APK.")
    }
  }

  private fun consumeProcessOutput(process: Process) {
    Thread {
          try {
            process.inputStream.bufferedReader().forEachLine { line ->
              if (line.isNotBlank()) {
                lastXrayLog = line.take(500)
              }
            }
          } catch (_: Exception) {}
        }
        .apply {
          name = "v2dex-xray-log"
          isDaemon = true
          start()
        }
  }

  data class AndroidTunnelStatus(
      val connected: Boolean = false,
      val connecting: Boolean = false,
      val mode: String = "full",
      val backend: String = "app-proxy",
      val lastConnectedAt: String? = null,
      val lastError: String? = null,
      val activeConfigPath: String? = null,
      val binaryPath: String? = null,
  )

  companion object {
    private const val NOTIFICATION_CHANNEL_ID = "v2dex_tunnel"
    private const val NOTIFICATION_ID = 43080
    private const val VPN_MTU = 1280
    private const val VPN_IPV4_ADDRESS = "198.18.0.1"
    private const val VPN_IPV6_ADDRESS = "fdfe:dcba:9876::1"
    @Volatile private var activeService: V2DexVpnService? = null
    @Volatile var status = AndroidTunnelStatus()
    @Volatile var lastXrayLog: String? = null

    fun stopActiveTunnel(): Boolean {
      val service = activeService ?: return false
      service.requestStopXray()
      return true
    }
  }
}

private fun isoNow(): String {
  val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
  formatter.timeZone = TimeZone.getTimeZone("UTC")
  return formatter.format(Date())
}
