package com.example.peacock.ui.screen.detail

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.peacock.R
import com.example.peacock.feature.runtime.DiagnosticsState
import com.example.peacock.feature.runtime.GlobalState
import com.example.peacock.util.Formatters

@Composable
fun TelemetryCard(
    global: GlobalState,
    diagnostics: DiagnosticsState,
    enabled: Boolean = true,
    onRefresh: () -> Unit,
    onClearDiagnostics: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    ElevatedCard(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text("DEVICE", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.secondary)
            Text(
                text = stringResource(R.string.device_information),
                style = MaterialTheme.typography.titleLarge,
            )
            Text(
                text = stringResource(R.string.chip_temp, Formatters.tempLabel(diagnostics.tempCx100)),
                style = MaterialTheme.typography.headlineMedium,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly,
            ) {
                Metric(Formatters.voltageLabel(diagnostics.vddaMv), "VOLTAGE")
                Metric(diagnostics.rxCount.toString(), "RX")
                Metric(global.deviceAddr.toString(), "ADDR")
            }
            Text(
                text = stringResource(
                    R.string.device_addr_save_state,
                    global.deviceAddr,
                    Formatters.saveStateLabel(context, global.saveState),
                ),
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
            Text(stringResource(R.string.diag_rx, diagnostics.rxCount, diagnostics.rxOverflow))
            Text(stringResource(R.string.diag_tx, diagnostics.txDrop, diagnostics.parseError))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Button(onClick = onRefresh, enabled = enabled, modifier = Modifier.weight(1f)) {
                    Text(stringResource(R.string.refresh_status))
                }
                OutlinedButton(onClick = onClearDiagnostics, enabled = enabled, modifier = Modifier.weight(1f)) {
                    Text(stringResource(R.string.clear_diagnostics))
                }
            }
        }
    }
}

@Composable
private fun Metric(value: String, label: String) {
    Column(horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally) {
        Text(value, style = MaterialTheme.typography.titleMedium)
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
