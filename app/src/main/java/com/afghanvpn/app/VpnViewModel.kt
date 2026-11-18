package com.afghanvpn.app

import android.app.Application
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.wireguard.android.backend.Tunnel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.net.SocketTimeoutException
import java.net.UnknownHostException

class VpnViewModel(app: Application) : AndroidViewModel(app) {
    private val vpn = VpnController.get(app)
    private val store = SecureStore(app)
    val registered = mutableStateOf(store.token != null)
    val servers = mutableStateOf<List<Server>>(emptyList())
    val loading = mutableStateOf(false)
    val error = mutableStateOf<String?>(null)
    val info = mutableStateOf<String?>(null)
    val publicIp = mutableStateOf<String?>(null)
    val selected = mutableStateOf<Server?>(null)
    val status = mutableStateOf(Status.DISCONNECTED)
    val rxBps = mutableStateOf(0L); val txBps = mutableStateOf(0L)
    val rxTotal = mutableStateOf(0L); val txTotal = mutableStateOf(0L)
    val seconds = mutableStateOf(0L)
    val linkOk = mutableStateOf(true)          // false = tunnel is up but the server stopped answering (traffic is blocked)
    val killSwitchAck = mutableStateOf(store.killSwitchAck)
    private var statsJob: Job? = null

    init {
        System.setProperty("http.keepAlive", "false")
        Api.token = store.token
        // If Android (or another VPN app) shuts the tunnel down behind our back, say so instead of showing "protected".
        viewModelScope.launch {
            vpn.tunnelState.collect { st -> if (st == Tunnel.State.DOWN && status.value == Status.CONNECTED) onUnexpectedDown() }
        }
        // The tunnel lives in a system service. If the screen was closed and reopened, show the TRUE state.
        val live = vpn.session
        if (vpn.tunnelState.value == Tunnel.State.UP && live != null) {
            selected.value = live.server; publicIp.value = live.ip; status.value = Status.CONNECTED
            info.value = "Verified: your traffic exits via ${live.server.flag} ${live.server.country}"
            startStats()
        } else if (vpn.tunnelState.value == Tunnel.State.UP) {
            viewModelScope.launch { runCatching { vpn.down() } }   // unknown leftover tunnel: close it rather than pretend
        }
        if (registered.value) refresh()
    }

    private fun friendly(e: Exception): String = when (e) {
        is ApiException -> e.message ?: "Server error"
        is SocketTimeoutException, is UnknownHostException -> "Cannot reach the AFGHAN VPN service. Check your internet connection."
        else -> "Connection failed: ${e.message}"
    }

    fun setKillAck(v: Boolean) { store.killSwitchAck = v; killSwitchAck.value = v }

    fun reconnect() { viewModelScope.launch { disconnect().join(); connect() } }

    private fun logout() { store.token = null; Api.token = null; registered.value = false }

    private fun resetLiveState() {
        statsJob?.cancel(); status.value = Status.DISCONNECTED; info.value = null; publicIp.value = null; linkOk.value = true
        rxBps.value = 0; txBps.value = 0; seconds.value = 0
    }

    private fun onUnexpectedDown() {
        val s = vpn.session; vpn.session = null
        resetLiveState()
        error.value = "The VPN was turned off by Android or another app. Your traffic is NOT protected."
        if (s != null) viewModelScope.launch { runCatching { Api.disconnect(s.publicKey) } }
    }

    fun register(code: String) = viewModelScope.launch {
        loading.value = true; error.value = null
        try { val t = Api.register(code.trim()); store.token = t; Api.token = t; registered.value = true; refresh() }
        catch (e: Exception) { error.value = friendly(e) }
        loading.value = false
    }

    fun refresh() = viewModelScope.launch {
        loading.value = true
        try { servers.value = Api.servers(); error.value = null }
        catch (e: Exception) { if (e is ApiException && e.code == 401) logout(); error.value = friendly(e) }
        loading.value = false
    }

    /** Call only after Android VPN permission was granted. */
    fun connect() {
        val s = selected.value ?: return
        if (status.value != Status.DISCONNECTED) return
        status.value = Status.CONNECTING; error.value = null; publicIp.value = null
        viewModelScope.launch {
            var pub: String? = null
            try {
                val kp = vpn.newKeyPair(); pub = kp.publicKey.toBase64()
                info.value = "Requesting secure session…"
                val ci = Api.connect(s.id, pub)
                info.value = "Starting encrypted tunnel…"
                if (vpn.up(vpn.buildConfig(kp.privateKey.toBase64(), ci)) != Tunnel.State.UP) error("Tunnel did not start")
                info.value = "Verifying your new IP address…"
                var who: Who? = null; var last: Exception? = null
                for (i in 1..3) {
                    try { who = Api.whoami(); break } catch (e: Exception) { last = e; delay(1500) }
                }
                if (who == null) throw last ?: IllegalStateException("Verification failed")
                if (who.serverId != s.id) error("Safety check failed: your traffic is not leaving through ${s.country}. Disconnected.")
                vpn.session = Session(s, pub, who.ip)
                publicIp.value = who.ip; linkOk.value = true; status.value = Status.CONNECTED
                info.value = "Verified: your traffic exits via ${s.flag} ${s.country}"
                startStats()
            } catch (e: Exception) {
                runCatching { vpn.down() }
                pub?.let { k -> runCatching { Api.disconnect(k) } }   // tunnel is down now, so this goes direct
                status.value = Status.DISCONNECTED; info.value = null
                if (e is ApiException && e.code == 401) logout()
                error.value = if (e is IllegalStateException) e.message else friendly(e)
            }
        }
    }

    fun disconnect() = viewModelScope.launch {
        val prev = status.value
        val s = vpn.session
        status.value = Status.DISCONNECTED          // set first so the "unexpected shutdown" watcher stays quiet
        try { vpn.down() } catch (e: Exception) {
            status.value = prev; error.value = "Disconnect error: ${e.message}"; return@launch   // tunnel still up: tell the truth
        }
        resetLiveState()
        s?.let { runCatching { Api.disconnect(it.publicKey) } }
        refresh()
    }

    private fun startStats() {
        statsJob?.cancel()
        statsJob = viewModelScope.launch {
            var lastRx = 0L; var lastTx = 0L; seconds.value = 0
            while (isActive) {
                delay(1000); seconds.value += 1
                val (rx, tx) = vpn.stats() ?: continue
                vpn.handshakeAgeMs()?.let { linkOk.value = it < 180_000 }
                rxBps.value = rx - lastRx; txBps.value = tx - lastTx
                rxTotal.value = rx; txTotal.value = tx; lastRx = rx; lastTx = tx
            }
        }
    }
}
