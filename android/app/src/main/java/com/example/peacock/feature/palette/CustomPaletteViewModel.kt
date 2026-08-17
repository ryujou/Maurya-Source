package com.example.peacock.feature.palette

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class CustomPaletteViewModel(private val repository: CustomPaletteRepository) : ViewModel() {
    val state: StateFlow<CustomPaletteState> = repository.state

    fun save(existingId: String?, revision: Int, nameZh: String, nameJa: String,
             hex: String, avatar: ByteArray, onResult: (Result<CustomPaletteEntry>) -> Unit) {
        viewModelScope.launch {
            onResult(runCatching { withContext(Dispatchers.IO) {
                repository.save(existingId, revision, nameZh, nameJa, hex, avatar)
            } })
        }
    }

    fun delete(entry: CustomPaletteEntry, onResult: (Result<Unit>) -> Unit = {}) {
        viewModelScope.launch {
            onResult(runCatching { withContext(Dispatchers.IO) { repository.delete(entry.id, entry.revision) } })
        }
    }

    suspend fun exportBackup(): ByteArray = withContext(Dispatchers.IO) { repository.exportBackup() }
    suspend fun importBackup(bytes: ByteArray, overwrite: Boolean): Int =
        withContext(Dispatchers.IO) { repository.importBackup(bytes, overwrite) }

    class Factory(private val repository: CustomPaletteRepository) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            CustomPaletteViewModel(repository) as T
    }
}
