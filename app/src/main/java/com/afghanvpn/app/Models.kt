package com.afghanvpn.app

data class Server(val id: String, val country: String, val code: String, val city: String, val load: Int, val online: Boolean) {
    val flag: String get() = code.uppercase().map { String(Character.toChars(0x1F1E6 + (it - 'A'))) }.joinToString("")
}
data class ConnectInfo(val address: String, val dns: String, val serverPublicKey: String, val endpoint: String)
data class Who(val ip: String, val serverId: String?)
enum class Status { DISCONNECTED, CONNECTING, CONNECTED }
/** What is connected right now (public information only; no private key). */
data class Session(val server: Server, val publicKey: String, val ip: String)
