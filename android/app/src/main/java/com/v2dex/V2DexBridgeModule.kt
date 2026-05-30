package com.v2dex

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.net.Uri
import android.provider.MediaStore
import android.os.Build
import android.util.Base64
import android.util.Log
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import com.facebook.react.bridge.ActivityEventListener
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.BaseActivityEventListener
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.URI
import java.net.NetworkInterface
import java.net.Proxy
import java.net.Socket
import java.net.URL
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.util.Date
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject

class V2DexBridgeModule(private val reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {
  private var pendingStart: PendingStart? = null
  private var pendingQrScan: Promise? = null
  private var pendingQrImage: Promise? = null

  private val activityListener: ActivityEventListener =
      object : BaseActivityEventListener() {
        override fun onActivityResult(
            activity: Activity?,
            requestCode: Int,
            resultCode: Int,
            data: Intent?
        ) {
          when (requestCode) {
            VPN_REQUEST_CODE -> {
              val start = pendingStart ?: return
              pendingStart = null

              if (resultCode != Activity.RESULT_OK) {
                start.promise.reject("E_VPN_PERMISSION", "Android VPN permission was not granted.")
                return
              }

              startVpn(start.configJson, start.mode, start.appRulesJson, start.promise)
            }
            QR_SCAN_REQUEST_CODE -> {
              val promise = pendingQrScan ?: return
              pendingQrScan = null
              val value = data?.getStringExtra(QrScanActivity.EXTRA_QR_VALUE)
              if (resultCode == Activity.RESULT_OK && !value.isNullOrBlank()) {
                promise.resolve(value)
              } else {
                promise.reject("E_QR_SCAN_CANCELLED", "QR scan was cancelled.")
              }
            }
            QR_IMAGE_REQUEST_CODE -> {
              val promise = pendingQrImage ?: return
              pendingQrImage = null
              val uri = data?.data
              if (resultCode != Activity.RESULT_OK || uri == null) {
                promise.reject("E_QR_IMAGE_CANCELLED", "QR image selection was cancelled.")
                return
              }
              decodeQrFromImage(uri, promise)
            }
          }
        }
      }

  init {
    reactContext.addActivityEventListener(activityListener)
  }

  override fun getName(): String = "V2DexBridge"

  @ReactMethod
  fun importFromClipboard(promise: Promise) {
    val clipboard = reactContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    promise.resolve(clipboard.primaryClip?.getItemAt(0)?.coerceToText(reactContext)?.toString() ?: "")
  }

  @ReactMethod
  fun copyToClipboard(value: String, promise: Promise) {
    val clipboard = reactContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(android.content.ClipData.newPlainText("V2DEX", value))
    promise.resolve(null)
  }

  @ReactMethod
  fun scanQrFromCamera(promise: Promise) {
    val activity = currentActivity
    if (activity == null) {
      promise.reject("E_QR_ACTIVITY", "QR scanner requires an active screen.")
      return
    }

    pendingQrScan?.reject("E_QR_REPLACED", "A newer QR scan was started.")
    pendingQrScan = promise
    activity.startActivityForResult(Intent(activity, QrScanActivity::class.java), QR_SCAN_REQUEST_CODE)
  }

  @ReactMethod
  fun scanQrFromGallery(promise: Promise) {
    val activity = currentActivity
    if (activity == null) {
      promise.reject("E_QR_ACTIVITY", "QR image picker requires an active screen.")
      return
    }

    pendingQrImage?.reject("E_QR_REPLACED", "A newer QR image selection was started.")
    pendingQrImage = promise
    val intent =
        Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI).apply {
          type = "image/*"
        }
    activity.startActivityForResult(intent, QR_IMAGE_REQUEST_CODE)
  }

  private fun decodeQrFromImage(uri: Uri, promise: Promise) {
    try {
      val image = InputImage.fromFilePath(reactContext, uri)
      BarcodeScanning.getClient()
          .process(image)
          .addOnSuccessListener { barcodes ->
            val value = barcodes.firstOrNull { !it.rawValue.isNullOrBlank() }?.rawValue
            if (value.isNullOrBlank()) {
              promise.reject("E_QR_NOT_FOUND", "No QR code was found in this image.")
            } else {
              promise.resolve(value)
            }
          }
          .addOnFailureListener { error ->
            promise.reject("E_QR_DECODE", error.message ?: "QR decode failed.")
          }
    } catch (error: Exception) {
      promise.reject("E_QR_DECODE", error.message ?: "QR decode failed.")
    }
  }

  @ReactMethod
  fun importFromUri(uri: String, promise: Promise) {
    Thread {
      try {
        val source = uri.trim()
        val download =
            if (source.startsWith("http://", true) || source.startsWith("https://", true)) {
              downloadSubscription(source)
            } else {
              SubscriptionDownload(source, null)
            }
        val body = download.body
        val decoded = decodeSubscriptionBody(body)
        val nodeUris = extractNodeUris(decoded).ifEmpty { extractNodeUris(body) }
        val nodes = JSONArray()
        val usage = download.usage ?: JSONObject()
        var remainingBytes: Long? = null

        nodeUris.forEach { nodeUri ->
          if (nodeUri.startsWith("vless://", true)) {
            nodes.put(parseVlessNode(nodeUri))
            remainingBytes = remainingBytes ?: parseRemainingBytesFromName(nodeUri)
          }
        }

        if (!usage.has("remainingBytes")) {
          remainingBytes?.let { usage.put("remainingBytes", it) }
        }

        promise.resolve(
            JSONObject()
                .put("nodes", nodes)
                .apply {
                  if (usage.length() > 0) {
                    put("usage", usage)
                  }
                }
                .toString())
      } catch (error: Exception) {
        promise.reject("E_IMPORT_PROFILE", error.message ?: "Import failed.")
      }
    }.start()
  }

  @ReactMethod
  fun discoverInstalledApplications(promise: Promise) {
    Thread {
      try {
        val packageManager = reactContext.packageManager
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val knownNetworkPackages =
            setOf(
                "org.telegram.messenger",
                "org.thunderdog.challegram",
                "com.android.chrome",
                "com.chrome.beta",
                "com.chrome.dev",
                "com.chrome.canary",
                "com.google.android.googlequicksearchbox",
                "com.google.android.apps.bard",
                "com.openai.chatgpt",
                "com.microsoft.emmx",
                "org.mozilla.firefox")
        val launcherPackages =
            queryLauncherActivities(packageManager, launcherIntent)
                .map { it.activityInfo.packageName }
                .toMutableSet()

        knownNetworkPackages.forEach { packageName ->
          if (isPackageInstalled(packageManager, packageName)) {
            launcherPackages.add(packageName)
          }
        }

        val apps = Arguments.createArray()
        launcherPackages
            .filter { it != reactContext.packageName }
            .distinct()
            .mapNotNull { packageName -> applicationInfoForPackage(packageManager, packageName) }
            .sortedWith(
                compareBy<ApplicationInfo> {
                      if (knownNetworkPackages.contains(it.packageName)) 0 else 1
                    }
                    .thenBy { isSystemApp(it) }
                    .thenBy { it.loadLabel(packageManager).toString().lowercase() })
            .forEach { info ->
              val map = Arguments.createMap()
              val packageName = info.packageName
              map.putString("bundleId", packageName)
              map.putString("name", info.loadLabel(packageManager).toString())
              map.putString("processName", packageName)
              map.putBoolean("enabled", false)
              apps.pushMap(map)
            }

        promise.resolve(apps)
      } catch (error: Exception) {
        promise.reject("E_DISCOVER_APPS", error.message ?: "App discovery failed.")
      }
    }.start()
  }

  private fun isPackageInstalled(packageManager: PackageManager, packageName: String): Boolean =
      applicationInfoForPackage(packageManager, packageName) != null

  private fun queryLauncherActivities(packageManager: PackageManager, intent: Intent) =
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        packageManager.queryIntentActivities(
            intent,
            PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_ALL.toLong()))
      } else {
        @Suppress("DEPRECATION")
        packageManager.queryIntentActivities(intent, PackageManager.MATCH_ALL)
      }

  private fun applicationInfoForPackage(
      packageManager: PackageManager,
      packageName: String
  ): ApplicationInfo? =
      try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
          packageManager.getApplicationInfo(
              packageName,
              PackageManager.ApplicationInfoFlags.of(PackageManager.MATCH_ALL.toLong()))
        } else {
          @Suppress("DEPRECATION")
          packageManager.getApplicationInfo(packageName, PackageManager.MATCH_ALL)
        }
      } catch (_: Exception) {
        null
      }

  @ReactMethod
  fun loadAppState(promise: Promise) {
    promise.resolve(prefs().getString(PREF_APP_STATE, "") ?: "")
  }

  @ReactMethod
  fun saveAppState(stateJson: String, promise: Promise) {
    prefs().edit().putString(PREF_APP_STATE, stateJson).apply()
    promise.resolve(null)
  }

  @ReactMethod
  fun testProfileDownload(sourceValue: String, promise: Promise) {
    Thread {
      try {
        val download = downloadSubscription(sourceValue.trim())
        val body = download.body
        val decoded = decodeSubscriptionBody(body)
        val nodeUris = extractNodeUris(decoded).ifEmpty { extractNodeUris(body) }
        val remaining = download.usage?.optLong("remainingBytes")?.takeIf { it > 0 }
            ?: nodeUris.mapNotNull { parseRemainingBytesFromName(it) }.firstOrNull()
        val trafficText = remaining?.let { " Traffic left: ${formatBytes(it)}." } ?: ""
        promise.resolve("Downloaded ${nodeUris.size} config${if (nodeUris.size == 1) "" else "s"}.$trafficText")
      } catch (error: Exception) {
        promise.reject("E_DOWNLOAD_TEST", error.message ?: "Subscription download failed.")
      }
    }.start()
  }

  @ReactMethod
  fun testServerConnection(nodeJson: String, promise: Promise) {
    Thread {
      try {
        val node = JSONObject(nodeJson)
        val server = node.optString("server")
        val port = node.optInt("port")
        val startedAt = System.nanoTime()

        Socket().use { socket ->
          socket.connect(InetSocketAddress(server, port), 5000)
        }

        val latencyMs = ((System.nanoTime() - startedAt) / 1_000_000).toInt()
        val result = Arguments.createMap()
        result.putString("message", "Connected in ${latencyMs}ms")
        result.putInt("latencyMs", latencyMs)
        promise.resolve(result)
      } catch (error: Exception) {
        promise.reject("E_PING_TIMEOUT", error.message ?: "Ping timed out.")
      }
    }.start()
  }

  @ReactMethod
  fun testTunnelHttpLatency(url: String, promise: Promise) {
    Thread {
      try {
        val startedAt = System.nanoTime()
        val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", 43080))
        val connection = URL(url.trim()).openConnection(proxy) as HttpURLConnection

        connection.connectTimeout = 15000
        connection.readTimeout = 15000
        connection.requestMethod = "GET"
        connection.instanceFollowRedirects = false
        connection.setRequestProperty("Cache-Control", "no-cache")
        connection.setRequestProperty("Pragma", "no-cache")
        connection.setRequestProperty("User-Agent", "V2Dex/1.0")

        try {
          val status = connection.responseCode
          if (status !in 200..399) {
            throw IllegalStateException("HTTP probe failed with status $status.")
          }

          val latencyMs = ((System.nanoTime() - startedAt) / 1_000_000).toInt()
          val result = Arguments.createMap()
          result.putString("message", "Reached ${URL(url).host} in ${latencyMs}ms")
          result.putInt("latencyMs", latencyMs)
          result.putString("url", url)
          promise.resolve(result)
        } finally {
          connection.disconnect()
        }
      } catch (error: Exception) {
        promise.reject("E_TUNNEL_PING_TIMEOUT", error.message ?: "Tunnel ping timed out.")
      }
    }.start()
  }

  @ReactMethod
  fun getTunnelIpInfo(promise: Promise) {
    Thread {
      val endpoints =
          listOf(
              "http://ip-api.com/json/?fields=status,country,countryCode,query,message",
              "https://ipwho.is/")
      var lastError: Exception? = null

      for (endpoint in endpoints) {
        try {
          val payload = downloadViaLocalSocks(endpoint)
          val parsed = JSONObject(payload)
          val failed =
              parsed.optString("status").equals("fail", ignoreCase = true) ||
                  parsed.optBoolean("success", true) == false
          if (failed) {
            throw IllegalStateException(parsed.optString("message", "IP lookup failed."))
          }

          val result = Arguments.createMap()
          result.putString("ip", parsed.optString("query", parsed.optString("ip", "")))
          result.putString("country", parsed.optString("country", ""))
          result.putString("countryCode", parsed.optString("countryCode", parsed.optString("country_code", "")))
          promise.resolve(result)
          return@Thread
        } catch (error: Exception) {
          lastError = error
        }
      }

      promise.reject("E_TUNNEL_IP_INFO", lastError?.message ?: "IP lookup failed.")
    }.start()
  }

  private fun downloadViaLocalSocks(url: String): String {
    val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", 43080))
    val connection = URL(url).openConnection(proxy) as HttpURLConnection

    connection.connectTimeout = 12000
    connection.readTimeout = 12000
    connection.requestMethod = "GET"
    connection.instanceFollowRedirects = true
    connection.setRequestProperty("Accept", "application/json")
    connection.setRequestProperty("Cache-Control", "no-cache")
    connection.setRequestProperty("Pragma", "no-cache")
    connection.setRequestProperty("User-Agent", "V2Dex/1.0")

    return try {
      val status = connection.responseCode
      if (status !in 200..299) {
        throw IllegalStateException("IP lookup failed with status $status.")
      }

      connection.inputStream.bufferedReader(StandardCharsets.UTF_8).use { reader -> reader.readText() }
    } finally {
      connection.disconnect()
    }
  }

  @ReactMethod
  fun startTunnel(configJson: String, mode: String, appRulesJson: String, promise: Promise) {
    Log.d("V2DexBridge", "startTunnel requested mode=$mode configBytes=${configJson.length}")
    val vpnIntent = VpnService.prepare(reactContext)
    if (vpnIntent != null) {
      val activity = currentActivity
      if (activity == null) {
        promise.reject("E_VPN_PERMISSION", "Android VPN permission requires an active screen.")
        return
      }

      pendingStart = PendingStart(configJson, mode, appRulesJson, promise)
      activity.startActivityForResult(vpnIntent, VPN_REQUEST_CODE)
      return
    }

    startVpn(configJson, mode, appRulesJson, promise)
  }

  @ReactMethod
  fun stopTunnel(promise: Promise) {
    val stoppedInProcess = V2DexVpnService.stopActiveTunnel()
    reactContext.startService(Intent(reactContext, V2DexVpnService::class.java).setAction(ACTION_STOP))
    if (!stoppedInProcess) {
      V2DexVpnService.status = V2DexVpnService.status.copy(connected = false, connecting = false)
    }
    promise.resolve(null)
  }

  @ReactMethod
  fun getTunnelStatus(promise: Promise) {
    promise.resolve(statusMap())
  }

  private fun startVpn(configJson: String, mode: String, appRulesJson: String, promise: Promise) {
    Log.d("V2DexBridge", "starting V2DexVpnService mode=$mode")
    val intent =
        Intent(reactContext, V2DexVpnService::class.java)
            .setAction(ACTION_START)
            .putExtra(EXTRA_CONFIG_JSON, configJson)
            .putExtra(EXTRA_MODE, mode)
            .putExtra(EXTRA_APP_RULES_JSON, appRulesJson)

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      reactContext.startForegroundService(intent)
    } else {
      reactContext.startService(intent)
    }
    promise.resolve(statusMap())
  }

  private fun statusMap() =
      Arguments.createMap().apply {
        val status = V2DexVpnService.status
        putBoolean("connected", status.connected)
        putBoolean("connecting", status.connecting)
        putString("mode", status.mode)
        putString("backend", status.backend)
        status.lastError?.let { putString("lastError", it) }
        status.lastConnectedAt?.let { putString("lastConnectedAt", it) }
        status.activeConfigPath?.let { putString("activeConfigPath", it) }
        status.binaryPath?.let { putString("binaryPath", it) }
        putString("proxyHost", localNetworkAddress() ?: "0.0.0.0")
        putInt("proxyPort", 43080)
      }

  private fun localNetworkAddress(): String? {
    return try {
      val candidates =
          NetworkInterface.getNetworkInterfaces().toList()
              .filter { it.isUp && !it.isLoopback }
              .flatMap { networkInterface ->
                networkInterface.inetAddresses.toList().mapNotNull { address ->
                  val host = address.hostAddress ?: return@mapNotNull null
                  if (host.contains(":") || host.startsWith("127.") || host.startsWith("169.254.")) {
                    null
                  } else {
                    networkInterface.name to host
                  }
                }
              }

      candidates.firstOrNull { (name, host) ->
            isPrivateIpv4(host) &&
                (name.startsWith("wlan") || name.startsWith("swlan") || name.startsWith("ap"))
          }
          ?.second
          ?: candidates.firstOrNull { (_, host) -> isPrivateIpv4(host) }?.second
          ?: candidates.firstOrNull()?.second
    } catch (_: Exception) {
      null
    }
  }

  private fun isPrivateIpv4(address: String): Boolean {
    val parts = address.split('.').mapNotNull { it.toIntOrNull() }
    if (parts.size != 4) {
      return false
    }

    return parts[0] == 10 ||
        (parts[0] == 192 && parts[1] == 168) ||
        (parts[0] == 172 && parts[1] in 16..31)
  }

  private fun prefs() = reactContext.getSharedPreferences("v2dex", Context.MODE_PRIVATE)

  private fun downloadSubscription(source: String): SubscriptionDownload {
    val connection = URL(source).openConnection() as HttpURLConnection
    connection.connectTimeout = 10000
    connection.readTimeout = 10000
    connection.requestMethod = "GET"
    connection.setRequestProperty("Accept", "text/plain, application/octet-stream, */*")
    connection.setRequestProperty("User-Agent", "V2Dex/1.0")

    return try {
      val status = connection.responseCode
      if (status !in 200..299) {
        throw IllegalStateException("Subscription download failed with status $status.")
      }
      val body = connection.inputStream.bufferedReader(StandardCharsets.UTF_8).use { reader -> reader.readText() }
      SubscriptionDownload(body, parseSubscriptionUsage(connection.getHeaderField("subscription-userinfo")))
    } finally {
      connection.disconnect()
    }
  }

  private fun parseSubscriptionUsage(header: String?): JSONObject? {
    if (header.isNullOrBlank()) {
      return null
    }

    val values =
        header
            .split(";")
            .mapNotNull { part ->
              val pieces = part.trim().split("=", limit = 2)
              val key = pieces.getOrNull(0)?.trim()?.lowercase(Locale.US)
              val value = pieces.getOrNull(1)?.trim()?.toLongOrNull()
              if (key.isNullOrBlank() || value == null) null else key to value
            }
            .toMap()
    val upload = values["upload"] ?: 0L
    val download = values["download"] ?: 0L
    val total = values["total"]
    val used = upload + download
    val usage = JSONObject()

    usage.put("uploadBytes", upload)
    usage.put("downloadBytes", download)
    usage.put("usedBytes", used)
    total?.let {
      usage.put("totalBytes", it)
      usage.put("remainingBytes", (it - used).coerceAtLeast(0L))
    }
    values["expire"]?.let { usage.put("expiresAt", Date(it * 1000L).toString()) }

    return if (usage.length() > 0) usage else null
  }

  private fun decodeSubscriptionBody(value: String): String {
    if (value.contains("://")) {
      return value
    }

    val compact = value.trim().replace("\\s+".toRegex(), "")
    if (compact.isEmpty()) {
      return value
    }

    return try {
      val normalized = compact.replace('-', '+').replace('_', '/')
      val padded = normalized.padEnd(((normalized.length + 3) / 4) * 4, '=')
      String(Base64.decode(padded, Base64.DEFAULT), StandardCharsets.UTF_8)
    } catch (_: Exception) {
      value
    }
  }

  private fun extractNodeUris(value: String): List<String> =
      value
          .split("\\s+".toRegex())
          .map { it.trim() }
          .filter { it.matches("(?i)^(vless|hysteria2|tuic)://.+".toRegex()) }

  private fun parseVlessNode(uri: String): JSONObject {
    val parsed = URI(uri)
    val params = parseQuery(parsed.rawQuery ?: "")
    val wsHost = params["host"]
    val name = decodeComponent(parsed.rawFragment ?: "").ifBlank { "VLESS ${parsed.host}" }

    return JSONObject()
        .put("id", "node-${hashString(uri)}")
        .put("name", name)
        .put("protocol", "vless")
        .put("server", parsed.host)
        .put("port", if (parsed.port > 0) parsed.port else 443)
        .put("security", params["security"] ?: "none")
        .put("transport", params["type"] ?: "tcp")
        .put("path", params["path"] ?: "/")
        .put("uuid", decodeComponent(parsed.userInfo ?: ""))
        .put("rawUri", uri)
        .apply {
          putOptional("sni", params["sni"] ?: wsHost)
          putOptional("wsHost", wsHost)
          putOptional("flow", params["flow"])
          put("allowInsecure", listOf("1", "true").contains(params["allowInsecure"]?.lowercase()))
          putOptional("publicKey", params["pbk"] ?: params["publicKey"])
          putOptional("shortId", params["sid"] ?: params["shortId"])
          putOptional("fingerprint", params["fp"] ?: params["fingerprint"])
          params["alpn"]
              ?.split(",")
              ?.map { it.trim() }
              ?.filter { it.isNotEmpty() }
              ?.takeIf { it.isNotEmpty() }
              ?.let { values ->
                val alpn = JSONArray()
                values.forEach { value -> alpn.put(value) }
                put("alpn", alpn)
              }
        }
  }

  private fun parseRemainingBytesFromName(uri: String): Long? {
    val fragment = URI(uri).rawFragment ?: return null
    val name = decodeComponent(fragment)
    val match =
        Regex("""(?i)(\d+(?:\.\d+)?)\s*(TB|GB|MB|KB|B)""").find(name) ?: return null
    val amount = match.groupValues[1].toDoubleOrNull() ?: return null
    val multiplier =
        when (match.groupValues[2].uppercase(Locale.US)) {
          "TB" -> 1024.0 * 1024.0 * 1024.0 * 1024.0
          "GB" -> 1024.0 * 1024.0 * 1024.0
          "MB" -> 1024.0 * 1024.0
          "KB" -> 1024.0
          else -> 1.0
        }
    return (amount * multiplier).toLong()
  }

  private fun JSONObject.putOptional(key: String, value: String?) {
    if (!value.isNullOrBlank()) {
      put(key, value)
    }
  }

  private fun isSystemApp(info: ApplicationInfo): Boolean =
      (info.flags and ApplicationInfo.FLAG_SYSTEM) != 0 &&
          (info.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0

  private fun parseQuery(query: String): Map<String, String> =
      query
          .split("&")
          .filter { it.isNotBlank() }
          .associate { part ->
            val pieces = part.split("=", limit = 2)
            decodeComponent(pieces[0]) to decodeComponent(pieces.getOrElse(1) { "" })
          }

  private fun decodeComponent(value: String): String =
      URLDecoder.decode(value, StandardCharsets.UTF_8.name())

  private fun hashString(value: String): String {
    var hash = 7
    value.forEach { char -> hash = hash * 31 + char.code }
    return Integer.toHexString(hash)
  }

  private fun formatBytes(value: Long): String {
    val units = listOf("B", "KB", "MB", "GB", "TB")
    var amount = value.toDouble()
    var unitIndex = 0

    while (amount >= 1024.0 && unitIndex < units.lastIndex) {
      amount /= 1024.0
      unitIndex += 1
    }

    return String.format(Locale.US, "%.2f%s", amount, units[unitIndex])
  }

  private data class PendingStart(
      val configJson: String,
      val mode: String,
      val appRulesJson: String,
      val promise: Promise
  )

  private data class SubscriptionDownload(val body: String, val usage: JSONObject?)

  companion object {
    private const val VPN_REQUEST_CODE = 7030
    private const val QR_SCAN_REQUEST_CODE = 7031
    private const val QR_IMAGE_REQUEST_CODE = 7032
    private const val PREF_APP_STATE = "app_state"
  }
}
