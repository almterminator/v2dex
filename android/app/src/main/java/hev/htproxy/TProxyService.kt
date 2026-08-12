package hev.htproxy

import android.net.VpnService

open class TProxyService : VpnService() {
  external fun TProxyStartService(configPath: String, fd: Int): Boolean
  external fun TProxyStopService(): Boolean
  external fun TProxyIsRunning(): Boolean
  external fun TProxyGetStats(): LongArray

  companion object {
    @Volatile private var nativeLoaded = false

    @Synchronized
    fun ensureNativeLoaded() {
      if (!nativeLoaded) {
        System.loadLibrary("hev-socks5-tunnel")
        nativeLoaded = true
      }
    }
  }
}
