package com.afghanvpn.app

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/** Device token is stored encrypted with a key held in the Android Keystore. VPN private keys are never stored. */
class SecureStore(private val ctx: Context) {
    private companion object { const val NAME = "afghanvpn_secure" }

    private fun create() = EncryptedSharedPreferences.create(
        ctx, NAME, MasterKey.Builder(ctx).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM)

    // If the Keystore key and the stored file ever disagree (known Android problem), start clean instead of crashing.
    private val prefs = try { create() } catch (e: Exception) { ctx.deleteSharedPreferences(NAME); create() }

    /** The user's own statement that Android's Always-on VPN + "Block connections without VPN" is switched on. Apps cannot check this. */
    var killSwitchAck: Boolean
        get() = prefs.getBoolean("killswitch_ack", false)
        set(v) { prefs.edit().putBoolean("killswitch_ack", v).apply() }
    var token: String?
        get() = prefs.getString("token", null)
        set(v) { prefs.edit().apply { if (v == null) remove("token") else putString("token", v) }.apply() }
}
