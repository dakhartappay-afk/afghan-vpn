package com.afghanvpn.app

import android.app.Activity
import android.content.Intent
import android.provider.Settings
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.wireguard.android.backend.GoBackend

private val Bg = Color(0xFF05080F); private val Card = Color(0xFF0E1522)
private val Green = Color(0xFF1FE05A); private val Muted = Color(0xFF8A96A8)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(primary = Green, background = Bg, surface = Card)) {
                var welcome by rememberSaveable { mutableStateOf(true) }
                Crossfade(welcome, animationSpec = tween(700), label = "nav") { if (it) Welcome { welcome = false } else Gate() }
            }
        }
    }
}

@Composable
fun Welcome(onContinue: () -> Unit) {
    Column(Modifier.fillMaxSize().background(Bg).statusBarsPadding().navigationBarsPadding()) {
        // OFFICIAL IDENTITY IMAGE. Shown whole and unchanged: ContentScale.Fit = no cropping, no stretching.
        // Do NOT add crop, scale, colorFilter, alpha or blur here. The build checks the file is identical to the original.
        Image(painterResource(R.drawable.welcome_art), "AFGHAN VPN - Proud to be Afghan, Secure, Fast, Global",
            Modifier.weight(1f).fillMaxWidth(), contentScale = ContentScale.Fit)
        Box(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 16.dp).height(58.dp)
            .clip(RoundedCornerShape(29.dp))
            .background(Brush.horizontalGradient(listOf(Color(0xFF12C94A), Color(0xFF3DF47E))))
            .clickable(role = Role.Button, onClickLabel = "Continue to AFGHAN VPN", onClick = onContinue),
            contentAlignment = Alignment.Center) {
            Text("CONTINUE  →", color = Color(0xFF03110A), fontWeight = FontWeight.Black, fontSize = 18.sp, letterSpacing = 3.sp)
        }
    }
}

@Composable
fun Dashboard(vm: VpnViewModel = viewModel()) {
    val ctx = LocalContext.current
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { if (it.resultCode == Activity.RESULT_OK) vm.connect() }
    fun onTap() {
        when (vm.status.value) {
            Status.DISCONNECTED -> { val i = GoBackend.VpnService.prepare(ctx); if (i == null) vm.connect() else permission.launch(i) }
            Status.CONNECTED -> vm.disconnect()
            Status.CONNECTING -> {}
        }
    }
    val st = vm.status.value
    Column(Modifier.fillMaxSize().background(Bg).statusBarsPadding().navigationBarsPadding().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
            Text("AFGHAN ", fontWeight = FontWeight.Black, fontSize = 22.sp, color = Color.White)
            Text("VPN", fontWeight = FontWeight.Black, fontSize = 22.sp, color = Green)
        }
        Spacer(Modifier.height(24.dp))
        Text(when (st) { Status.CONNECTED -> if (vm.linkOk.value) "PROTECTED" else "LINK LOST - TRAFFIC BLOCKED"; Status.CONNECTING -> "CONNECTING…"; else -> "NOT CONNECTED" },
            color = if (st == Status.CONNECTED) (if (vm.linkOk.value) Green else Color(0xFFFF6B6B)) else Muted, fontWeight = FontWeight.Bold, fontSize = 16.sp, letterSpacing = 2.sp)
        Spacer(Modifier.height(16.dp))
        Box(Modifier.size(150.dp).clip(CircleShape).border(4.dp, if (st == Status.CONNECTED) Green else Muted, CircleShape)
            .background(Card).clickable(enabled = vm.selected.value != null && st != Status.CONNECTING) { onTap() }, contentAlignment = Alignment.Center) {
            if (st == Status.CONNECTING) CircularProgressIndicator(color = Green)
            else Text(if (st == Status.CONNECTED) "DISCONNECT" else "CONNECT", color = Color.White, fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.height(8.dp))
        Text(vm.selected.value?.let { "${it.flag} ${it.country} · ${it.city}" } ?: "Select a server below", color = Muted)
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Stat("↓ Download", "${fmt(vm.rxBps.value)}/s", Modifier.weight(1f))
            Stat("↑ Upload", "${fmt(vm.txBps.value)}/s", Modifier.weight(1f))
            Stat("Time", "%02d:%02d:%02d".format(vm.seconds.value / 3600, vm.seconds.value / 60 % 60, vm.seconds.value % 60), Modifier.weight(1f))
        }
        Text("Used: ↓ ${fmt(vm.rxTotal.value)}  ↑ ${fmt(vm.txTotal.value)}", color = Muted, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp))
        vm.info.value?.let { Text(it, color = Green, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp)) }
        vm.publicIp.value?.let { Text("Your public IP: $it", color = Color.White, fontSize = 13.sp) }
        if (st == Status.CONNECTED && !vm.linkOk.value) {
            Button(onClick = { vm.reconnect() }, modifier = Modifier.padding(top = 8.dp)) { Text("RECONNECT", color = Color.Black, fontWeight = FontWeight.Bold) }
        }
        Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(if (vm.killSwitchAck.value) "Kill switch: on (set by you)" else "Kill switch: NOT set up", fontSize = 12.sp,
                color = if (vm.killSwitchAck.value) Green else Color(0xFFFFB84D), modifier = Modifier.weight(1f))
            TextButton(onClick = { try { ctx.startActivity(Intent(Settings.ACTION_VPN_SETTINGS)) } catch (e: Exception) { ctx.startActivity(Intent(Settings.ACTION_SETTINGS)) } }) { Text("Open VPN settings", color = Green, fontSize = 12.sp) }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Checkbox(checked = vm.killSwitchAck.value, onCheckedChange = { vm.setKillAck(it) })
            Text("I turned on Always-on VPN + Block connections without VPN", color = Muted, fontSize = 11.sp)
        }
        vm.error.value?.let { Text(it, color = Color(0xFFFF6B6B), fontSize = 13.sp, modifier = Modifier.padding(top = 8.dp)) }
        Spacer(Modifier.height(12.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text("Locations", color = Color.White, fontWeight = FontWeight.Bold)
            TextButton(onClick = { vm.refresh() }) { Text("Refresh", color = Green) }
        }
        when {
            vm.loading.value -> CircularProgressIndicator(color = Green)
            vm.servers.value.isEmpty() -> Text("No servers available yet.", color = Muted)
            else -> LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(vm.servers.value) { s ->
                    val sel = vm.selected.value?.id == s.id
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Card)
                        .border(if (sel) 2.dp else 0.dp, Green, RoundedCornerShape(14.dp))
                        .clickable(enabled = st == Status.DISCONNECTED && s.online) { vm.selected.value = s }.padding(14.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Text(s.flag, fontSize = 28.sp); Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) { Text(s.country, color = Color.White, fontWeight = FontWeight.Bold); Text(s.city, color = Muted, fontSize = 12.sp) }
                        Text(if (s.online) "${s.load}% load" else "OFFLINE", color = if (s.online) Muted else Color(0xFFFF6B6B), fontSize = 12.sp)
                    }
                }
            }
        }
    }
}

@Composable
fun Stat(label: String, value: String, m: Modifier) {
    Column(m.clip(RoundedCornerShape(12.dp)).background(Card).padding(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(label, color = Muted, fontSize = 11.sp); Text(value, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
    }
}

fun fmt(b: Long): String = when { b >= 1L shl 30 -> "%.2f GB".format(b / 1073741824.0); b >= 1L shl 20 -> "%.1f MB".format(b / 1048576.0); b >= 1024 -> "%.0f KB".format(b / 1024.0); else -> "$b B" }
