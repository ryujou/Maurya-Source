package com.example.peacock.feature.ota

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class OtaViewModel(private val coordinator: OtaCoordinator) : ViewModel() {
    private val _state = MutableStateFlow(OtaUiState())
    val state: StateFlow<OtaUiState> = _state.asStateFlow()
    private var job: Job? = null
    private var infoJob: Job? = null

    fun start(deviceAddress: Int) {
        if (job?.isActive == true) return
        job = viewModelScope.launch {
            runCatching { coordinator.run(deviceAddress) { _state.value = it } }
        }
    }

    fun cancel(deviceAddress: Int) {
        if (!_state.value.canCancel) return
        job?.cancel()
        job = viewModelScope.launch {
            coordinator.cancel(deviceAddress)
            _state.value = OtaUiState()
        }
    }

    fun refreshInstalledVersion(deviceAddress: Int) {
        if (job?.isActive == true || infoJob?.isActive == true) return
        infoJob = viewModelScope.launch {
            runCatching { coordinator.readInstalledVersion(deviceAddress) }
                .onSuccess { version ->
                    _state.value = _state.value.copy(installedVersion = version)
                }
        }
    }

    class Factory(private val coordinator: OtaCoordinator) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            OtaViewModel(coordinator) as T
    }
}
