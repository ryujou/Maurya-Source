package com.example.peacock.ui

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.example.peacock.feature.share.ShareRepository
import com.example.peacock.ui.i18n.AppLanguageManager
import com.example.peacock.ui.theme.MauryaTheme

class MainActivity : AppCompatActivity() {
    private var incomingShareToken by mutableStateOf<String?>(null)
    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        AppLanguageManager.initialize(this, allowManualOverride = true)
        super.onCreate(savedInstanceState)
        acceptShareIntent(intent)
        enableEdgeToEdge()
        setContent {
            MauryaTheme {
                MauryaApp(
                    requestPermissions = { permissionLauncher.launch(it) },
                    incomingShareToken = incomingShareToken,
                    onShareTokenConsumed = { incomingShareToken = null },
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        acceptShareIntent(intent)
    }

    private fun acceptShareIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        incomingShareToken = intent.dataString?.let { value ->
            runCatching { ShareRepository.parseToken(value) }.getOrNull()
        }
    }
}
