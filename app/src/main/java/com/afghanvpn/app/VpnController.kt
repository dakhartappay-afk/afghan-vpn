package com.afghanvpn.app

import android.content.Context
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import com.wireguard.config.InetNetwork
import com.wireguard.config.Interface
import com.wireguard.config.Peer
import com.wireguard.crypto.KeyPair
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.withContext
import java.net.InetAddress

/**
 * Real WireGuard tunnel via the official wireguard-android library.
 * ONE instance for the whole app process: the tunnel lives in a system service and outlives the screen,
 * so the screen (ViewModel) must be able to find it again after being closed and reopened.
 */
class VpnController private constructor(ctx: Context) {
    companion object {
        @Volatile private var inst: VpnController? = null
        fun get(ctx: Context): VpnController =
            inst ?: synchronized(this) { inst ?: VpnController(ctx.applicationContext).also { inst = it } }
    }

    private val backend = GoBackend(ctx)
    val tunnelState = MutableStateFlow(Tunnel.State.DOWN)
    @Volatile var session: Session? = null

    private val tunnel = object : Tunnel {
        override fun getName() = "afghanvpn"
        override fun onStateChange(newState: Tunnel.State) { tunnelState.value = newState }
    }

    fun newKeyPair() = KeyPair()

    fun buildConfig(privateKeyB64: String, info: ConnectInfo): Config {
        val ib = Interface.Builder().parsePrivateKey(privateKeyB64).addAddress(InetNetwork.parse(info.address))
        // DNS must be literal IP addresses (a hostname would be looked up OUTSIDE the tunnel = DNS leak)
        val ip4 = Regex("""\d{1,3}(\.\d{1,3}){3}""")
        val dns = info.dns.split(",").map { it.trim() }.filter { it.isNotEmpty() }
        require(dns.isNotEmpty() && dns.all { ip4.matches(it) }) { "Server sent invalid DNS settings" }
        dns.forEach { ib.addDnsServer(InetAddress.getByName(it)) }
        val iface = ib.build()
        val peer = Peer.Builder()
            .parsePublicKey(info.serverPublicKey)
            .parseEndpoint(info.endpoint)
            .addAllowedIp(InetNetwork.parse("0.0.0.0/0"))
            .addAllowedIp(InetNetwork.parse("::/0"))   // route IPv6 through tunnel too (leak protection)
            .setPersistentKeepalive(25)
            .build()
        return Config.Builder().setInterface(iface).addPeer(peer).build()
    }

    suspend fun up(cfg: Config): Tunnel.State = withContext(Dispatchers.IO) { backend.setState(tunnel, Tunnel.State.UP, cfg) }
    suspend fun down() { withContext(Dispatchers.IO) { backend.setState(tunnel, Tunnel.State.DOWN, null) }; session = null }

    /** Age of the latest WireGuard handshake in ms, or null if unknown. A healthy tunnel re-handshakes about every 2 minutes. */
    fun handshakeAgeMs(): Long? = try {
        val s = backend.getStatistics(tunnel)
        val key = s.peers().firstOrNull()
        val ts = if (key == null) 0L else (s.peer(key)?.latestHandshakeEpochMillis() ?: 0L)
        if (ts == 0L) null else System.currentTimeMillis() - ts
    } catch (e: Exception) { null }

    /** Real byte counters from the tunnel, or null if not connected. */
    fun stats(): Pair<Long, Long>? = try {
        val s = backend.getStatistics(tunnel); s.totalRx() to s.totalTx()
    } catch (e: Exception) { null }
}
