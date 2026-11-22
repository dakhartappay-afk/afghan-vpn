package com.afghanvpn.app

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel

@Composable
fun Gate(vm: VpnViewModel = viewModel()) { if (BuildConfig.DEBUG || vm.registered.value) Dashboard(vm) else Register(vm) }

@Composable
fun Register(vm: VpnViewModel) {
    var code by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize().background(Color(0xFF05080F)).statusBarsPadding().padding(24.dp),
        verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Text("AFGHAN VPN", color = Color.White, fontWeight = FontWeight.Black, fontSize = 26.sp)
        Spacer(Modifier.height(8.dp))
        Text("Enter your invite code to activate this device", color = Color(0xFF8A96A8))
        Spacer(Modifier.height(20.dp))
        OutlinedTextField(value = code, onValueChange = { code = it }, singleLine = true, label = { Text("AFG-XXXXXX-XXXXXX") }, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(16.dp))
        Button(onClick = { vm.register(code) }, enabled = code.isNotBlank() && !vm.loading.value, modifier = Modifier.fillMaxWidth().height(52.dp)) {
            Text("ACTIVATE", fontWeight = FontWeight.Bold, color = Color.Black)
        }
        vm.error.value?.let { Text(it, color = Color(0xFFFF6B6B), modifier = Modifier.padding(top = 12.dp)) }
    }
}
