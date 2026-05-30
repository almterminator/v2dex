package hev.htproxy

import android.net.VpnService

open class TProxyService : VpnService() {
  external fun TProxyStartService(configPath: String, fd: Int)
  external fun TProxyStopService()
  external fun TProxyGetStats(): LongArray

  companion object {
    init {
      System.loadLibrary("hev-socks5-tunnel")
    }
  }
}
