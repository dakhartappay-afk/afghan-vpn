package com.afghanvpn.app

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class ApiException(val code: Int, message: String) : Exception(message)

/** Talks to the AFGHAN VPN backend over HTTPS only. Real data only. */
object Api {
    private val base = BuildConfig.API_BASE_URL.trimEnd('/')
    @Volatile var token: String? = null
    init { require(base.startsWith("https://")) { "API_BASE_URL must start with https://" } }

    private suspend fun call(method: String, path: String, body: JSONObject? = null, timeoutMs: Int = 15000): String = withContext(Dispatchers.IO) {
        val c = URL(base + path).openConnection() as HttpURLConnection
        try {
            c.requestMethod = method; c.connectTimeout = timeoutMs; c.readTimeout = timeoutMs
            c.useCaches = false
            c.setRequestProperty("Connection", "close")   // never reuse a connection made outside the tunnel
            token?.let { c.setRequestProperty("Authorization", "Bearer $it") }
            if (body != null) { c.doOutput = true; c.setRequestProperty("Content-Type", "application/json"); c.outputStream.use { it.write(body.toString().toByteArray()) } }
            val ok = c.responseCode in 200..299
            val text = (if (ok) c.inputStream else c.errorStream)?.bufferedReader()?.readText().orEmpty()
            if (!ok) {
                val detail = try { JSONObject(text).getString("detail") } catch (e: Exception) { "Request failed (${c.responseCode})" }
                throw ApiException(c.responseCode, detail)
            }
            text
        } finally { c.disconnect() }
    }

    suspend fun register(code: String): String = JSONObject(call("POST", "/v1/register", JSONObject().put("code", code))).getString("token")

    suspend fun servers(): List<Server> {
        val a = JSONArray(call("GET", "/v1/servers"))
        return (0 until a.length()).map { val o = a.getJSONObject(it)
            Server(o.getString("id"), o.getString("country"), o.getString("code"), o.getString("city"), o.optInt("load", 0), o.optBoolean("online", false)) }
    }

    suspend fun connect(serverId: String, publicKey: String): ConnectInfo {
        val o = JSONObject(call("POST", "/v1/connect", JSONObject().put("server_id", serverId).put("public_key", publicKey)))
        return ConnectInfo(o.getString("address"), o.getString("dns"), o.getString("server_public_key"), o.getString("endpoint"))
    }

    suspend fun disconnect(publicKey: String) { call("POST", "/v1/disconnect", JSONObject().put("public_key", publicKey)) }

    /** Asks OUR backend which IP it sees. After connecting, this must be the VPN server's IP. */
    suspend fun whoami(): Who {
        val o = JSONObject(call("GET", "/v1/whoami", timeoutMs = 7000))
        return Who(o.getString("ip"), if (o.isNull("server_id")) null else o.getString("server_id"))
    }
}
