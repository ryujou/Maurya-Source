package com.example.peacock.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.SystemClock
import com.example.peacock.R
import com.example.peacock.protocol.ModbusCodec
import com.example.peacock.util.PermissionUtils
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull

class BleManager(
    context: Context,
) {
    private val appContext = context.applicationContext
    private val btManager = appContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val btAdapter: BluetoothAdapter? = btManager.adapter
    private val scanner: BluetoothLeScanner? get() = btAdapter?.bluetoothLeScanner

    private val _scanResults = MutableStateFlow<List<BleDeviceItem>>(emptyList())
    val scanResults = _scanResults.asStateFlow()

    private val _session = MutableStateFlow(
        BleSessionState(
            connectionText = appContext.getString(R.string.ble_not_connected),
            servicesText = appContext.getString(R.string.ble_services_not_found),
        ),
    )
    val session = _session.asStateFlow()

    private var scanCallback: ScanCallback? = null
    private var gatt: BluetoothGatt? = null
    private var writeChar: BluetoothGattCharacteristic? = null
    private var notifyChar: BluetoothGattCharacteristic? = null
    private var lastConnectedDevice: BleDeviceItem? = null

    private val requestMutex = Mutex()
    private var pendingWrite: CompletableDeferred<Unit>? = null
    private var pendingResponse: CompletableDeferred<ByteArray>? = null
    private var notifyBuffer = ByteArray(0)

    @SuppressLint("MissingPermission")
    fun startScan(filterFfe0: Boolean) {
        if (!PermissionUtils.hasBlePermissions(appContext)) {
            updateSession {
                it.copy(
                    connectionText = appContext.getString(R.string.ble_scan_permission_required),
                    isScanning = false,
                )
            }
            return
        }

        val adapter = btAdapter
        val bleScanner = scanner
        if (adapter == null) {
            updateSession { it.copy(connectionText = appContext.getString(R.string.ble_adapter_missing)) }
            return
        }
        if (!adapter.isEnabled) {
            updateSession { it.copy(connectionText = appContext.getString(R.string.ble_enable_bluetooth)) }
            return
        }
        if (bleScanner == null) {
            updateSession { it.copy(connectionText = appContext.getString(R.string.ble_scanner_unavailable)) }
            return
        }
        if (_session.value.isScanning) return

        _scanResults.value = emptyList()
        updateSession {
            it.copy(
                isScanning = true,
                connectionText = if (filterFfe0) {
                    appContext.getString(R.string.ble_scanning_ffe0)
                } else {
                    appContext.getString(R.string.ble_scanning)
                },
            )
        }

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setReportDelay(0L)
            .build()

        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                if (!PermissionUtils.hasBleConnectPermission(appContext)) return
                val device = result.device ?: return
                val address = device.address ?: return
                // Prefer the current advertising name over Android's cached device name.
                val name = result.scanRecord?.deviceName ?: device.name ?: "(no name)"
                val advertisedServices = result.scanRecord
                    ?.serviceUuids
                    ?.map { it.uuid }
                    .orEmpty()
                if (!BleAdvertisementMatcher.matches(
                        filterMaurya = filterFfe0,
                        name = name,
                        advertisedServices = advertisedServices,
                    )
                ) {
                    return
                }
                val item = BleDeviceItem(name, address, result.rssi, device)
                val current = _scanResults.value.toMutableList()
                val index = current.indexOfFirst { it.address == address }
                if (index >= 0) current[index] = item else current.add(item)
                _scanResults.value = current
            }

            override fun onScanFailed(errorCode: Int) {
                updateSession {
                    it.copy(
                        isScanning = false,
                        connectionText = appContext.getString(R.string.ble_scan_failed, errorCode),
                    )
                }
            }
        }

        scanCallback = callback
        // Do not use Android's controller-side UUID ScanFilter here. Several
        // phones can display the Maurya advertisement in system settings but
        // omit its 16-bit UUID while applying hardware filters, so the app
        // never receives a callback. Receive advertisements unfiltered and
        // apply the Maurya/FFE0 predicate above instead.
        bleScanner.startScan(null, settings, callback)
    }

    @SuppressLint("MissingPermission")
    fun stopScan() {
        if (PermissionUtils.hasBleScanPermission(appContext)) {
            scanner?.let { bleScanner ->
                scanCallback?.let { callback ->
                    runCatching { bleScanner.stopScan(callback) }
                }
            }
        }
        scanCallback = null
        updateSession {
            it.copy(
                isScanning = false,
                connectionText = if (it.selectedDevice == null) {
                    appContext.getString(R.string.ble_scan_stopped)
                } else {
                    it.connectionText
                },
            )
        }
    }

    @SuppressLint("MissingPermission")
    fun connect(deviceItem: BleDeviceItem) {
        if (!PermissionUtils.hasBleConnectPermission(appContext)) {
            updateSession {
                it.copy(
                    connectionText = appContext.getString(R.string.ble_connect_permission_required),
                    isReady = false,
                )
            }
            return
        }

        stopScan()
        disconnect()
        lastConnectedDevice = deviceItem
        updateSession {
            it.copy(
                selectedDevice = deviceItem,
                connectionText = appContext.getString(R.string.ble_connecting),
                servicesText = appContext.getString(R.string.ble_services_not_found),
                negotiatedMtu = 23,
                isReady = false,
            )
        }
        gatt = deviceItem.device.connectGatt(
            appContext,
            false,
            gattCallback,
            BluetoothDevice.TRANSPORT_LE,
        )
    }

    fun reconnect() {
        lastConnectedDevice?.let(::connect)
    }

    suspend fun reconnectUntilReady(
        timeoutMs: Long = 45_000,
        attemptTimeoutMs: Long = 7_000,
    ): Boolean {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        var retryDelayMs = 500L

        while (SystemClock.elapsedRealtime() < deadline) {
            if (_session.value.isReady) return true

            reconnect()
            val remainingMs = (deadline - SystemClock.elapsedRealtime()).coerceAtLeast(1L)
            val connected = withTimeoutOrNull(minOf(attemptTimeoutMs, remainingMs)) {
                session.first { it.isReady }
            } != null
            if (connected) return true

            disconnect()
            val delayMs = minOf(retryDelayMs, (deadline - SystemClock.elapsedRealtime()).coerceAtLeast(0L))
            if (delayMs > 0L) delay(delayMs)
            retryDelayMs = (retryDelayMs * 2).coerceAtMost(3_000L)
        }
        return false
    }

    @SuppressLint("MissingPermission")
    fun disconnect() {
        pendingWrite?.cancel()
        pendingResponse?.cancel()
        pendingWrite = null
        pendingResponse = null
        notifyBuffer = ByteArray(0)
        if (PermissionUtils.hasBleConnectPermission(appContext)) {
            runCatching { gatt?.disconnect() }
            runCatching { gatt?.close() }
        }
        gatt = null
        writeChar = null
        notifyChar = null
        updateSession {
            it.copy(
                connectionText = appContext.getString(R.string.ble_disconnected),
                servicesText = appContext.getString(R.string.ble_services_not_found),
                negotiatedMtu = 23,
                isReady = false,
            )
        }
    }

    @SuppressLint("MissingPermission")
    suspend fun transceive(
        request: ByteArray,
        timeoutMs: Long = 2_000,
    ): ByteArray = withContext(Dispatchers.IO) {
        requestMutex.withLock {
            check(PermissionUtils.hasBleConnectPermission(appContext)) {
                "Bluetooth connect permission unavailable"
            }
            val activeGatt = gatt ?: error("Not connected")
            val activeWrite = writeChar ?: error("FFE1 not found")
            check(_session.value.isReady) { "BLE service not ready" }

            notifyBuffer = ByteArray(0)
            val responseDeferred = CompletableDeferred<ByteArray>()
            pendingResponse = responseDeferred

            try {
                BleWriteChunker.chunkPayload(request, _session.value.negotiatedMtu).forEach { chunk ->
                    writeChunk(activeGatt, activeWrite, chunk)
                }
                withTimeout(timeoutMs) { responseDeferred.await() }
            } finally {
                pendingWrite?.cancel()
                pendingWrite = null
                pendingResponse = null
            }
        }
    }

    fun close() {
        stopScan()
        disconnect()
    }

    @SuppressLint("MissingPermission")
    private suspend fun writeChunk(
        activeGatt: BluetoothGatt,
        activeWrite: BluetoothGattCharacteristic,
        chunk: ByteArray,
    ) {
        val writeDeferred = CompletableDeferred<Unit>()
        pendingWrite = writeDeferred

        activeWrite.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        val writeAccepted = if (Build.VERSION.SDK_INT >= 33) {
            activeGatt.writeCharacteristic(
                activeWrite,
                chunk,
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
            ) == BluetoothStatusCodes.SUCCESS
        } else {
            @Suppress("DEPRECATION")
            activeWrite.value = chunk
            @Suppress("DEPRECATION")
            activeGatt.writeCharacteristic(activeWrite)
        }
        check(writeAccepted) { "BLE write request was not accepted" }

        try {
            withTimeout(1_500) { writeDeferred.await() }
        } finally {
            if (pendingWrite === writeDeferred) {
                pendingWrite = null
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun enableNotify(activeGatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
        if (!PermissionUtils.hasBleConnectPermission(appContext)) {
            updateSession {
                it.copy(
                    servicesText = appContext.getString(R.string.ble_notify_permission_unavailable),
                    isReady = false,
                )
            }
            return
        }
        val ok = activeGatt.setCharacteristicNotification(characteristic, true)
        val descriptor = characteristic.getDescriptor(UUID_CCCD)
        if (!ok || descriptor == null) {
            updateSession {
                it.copy(
                    servicesText = appContext.getString(R.string.ble_enable_notify_failed),
                    isReady = false,
                )
            }
            return
        }
        if (Build.VERSION.SDK_INT >= 33) {
            activeGatt.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
        } else {
            @Suppress("DEPRECATION")
            descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            @Suppress("DEPRECATION")
            activeGatt.writeDescriptor(descriptor)
        }
    }

    private fun handleNotification(bytes: ByteArray) {
        notifyBuffer += bytes
        val expectedLength = ModbusCodec.expectedResponseLength(notifyBuffer) ?: return
        if (notifyBuffer.size < expectedLength) return
        val frame = notifyBuffer.copyOf(expectedLength)
        notifyBuffer = ByteArray(0)
        pendingResponse?.complete(frame)
    }

    private fun updateSession(transform: (BleSessionState) -> BleSessionState) {
        _session.value = transform(_session.value)
    }

    @SuppressLint("MissingPermission")
    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(activeGatt: BluetoothGatt, status: Int, newState: Int) {
            if (this@BleManager.gatt !== activeGatt) {
                runCatching { activeGatt.close() }
                return
            }
            if (!PermissionUtils.hasBleConnectPermission(appContext)) {
                updateSession {
                    it.copy(
                        connectionText = appContext.getString(R.string.ble_notify_permission_unavailable),
                        servicesText = appContext.getString(R.string.ble_services_not_found),
                        isReady = false,
                    )
                }
                this@BleManager.gatt = null
                return
            }
            if (status != BluetoothGatt.GATT_SUCCESS) {
                updateSession {
                    it.copy(
                        connectionText = appContext.getString(R.string.ble_connect_failed, status),
                        isReady = false,
                    )
                }
                disconnect()
                return
            }
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    updateSession {
                        it.copy(
                            connectionText = appContext.getString(R.string.ble_connected),
                            servicesText = appContext.getString(R.string.ble_discovering_services),
                            isReady = false,
                        )
                    }
                    if (!activeGatt.discoverServices()) {
                        updateSession {
                            it.copy(
                                servicesText = appContext.getString(
                                    R.string.ble_service_discovery_not_started,
                                ),
                                isReady = false,
                            )
                        }
                    }
                }

                BluetoothProfile.STATE_DISCONNECTED -> {
                    updateSession {
                        it.copy(
                            connectionText = appContext.getString(R.string.ble_disconnected),
                            servicesText = appContext.getString(R.string.ble_services_not_found),
                            isReady = false,
                        )
                    }
                    runCatching { activeGatt.close() }
                    this@BleManager.gatt = null
                }
            }
        }

        override fun onServicesDiscovered(activeGatt: BluetoothGatt, status: Int) {
            if (this@BleManager.gatt !== activeGatt) return
            if (!PermissionUtils.hasBleConnectPermission(appContext)) {
                updateSession {
                    it.copy(
                        servicesText = appContext.getString(R.string.ble_notify_permission_unavailable),
                        isReady = false,
                    )
                }
                return
            }
            if (status != BluetoothGatt.GATT_SUCCESS) {
                updateSession {
                    it.copy(
                        servicesText = appContext.getString(R.string.ble_service_discovery_failed, status),
                        isReady = false,
                    )
                }
                return
            }

            val service = activeGatt.getService(UUID_FFE0)
            val foundWrite = service?.getCharacteristic(UUID_FFE1)
                ?: activeGatt.services.firstNotNullOfOrNull { svc ->
                    svc.getCharacteristic(UUID_FFE1) ?: svc.characteristics.firstOrNull { ch ->
                        (ch.properties and BluetoothGattCharacteristic.PROPERTY_WRITE) != 0
                    }
                }
            val foundNotify = service?.getCharacteristic(UUID_FFE2)
                ?: activeGatt.services.firstNotNullOfOrNull { svc ->
                    svc.getCharacteristic(UUID_FFE2) ?: svc.characteristics.firstOrNull { ch ->
                        (ch.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0
                    }
                }

            writeChar = foundWrite
            notifyChar = foundNotify
            if (foundWrite == null || foundNotify == null) {
                updateSession {
                    it.copy(
                        servicesText = appContext.getString(R.string.ble_missing_chars),
                        isReady = false,
                    )
                }
                return
            }

            updateSession {
                it.copy(
                    servicesText = appContext.getString(R.string.ble_enabling_notify),
                    isReady = false,
                )
            }
            // Android permits only one outstanding GATT operation. Negotiate
            // MTU first, then write CCCD; otherwise the first application
            // write can be rejected even though the UI already says ready.
            if (!activeGatt.requestMtu(247)) {
                enableNotify(activeGatt, foundNotify)
            }
        }

        override fun onDescriptorWrite(
            activeGatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) {
            if (this@BleManager.gatt !== activeGatt) return
            updateSession {
                it.copy(
                    servicesText = if (status == BluetoothGatt.GATT_SUCCESS) {
                        appContext.getString(R.string.ble_service_ready)
                    } else {
                        appContext.getString(R.string.ble_notify_enable_failed, status)
                    },
                    isReady = status == BluetoothGatt.GATT_SUCCESS,
                )
            }
        }

        override fun onMtuChanged(activeGatt: BluetoothGatt, mtu: Int, status: Int) {
            if (this@BleManager.gatt !== activeGatt) return
            if (status == BluetoothGatt.GATT_SUCCESS) {
                updateSession { it.copy(negotiatedMtu = mtu) }
            }
            notifyChar?.let { enableNotify(activeGatt, it) }
        }

        override fun onCharacteristicWrite(
            activeGatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            if (this@BleManager.gatt !== activeGatt) return
            if (status == BluetoothGatt.GATT_SUCCESS) {
                pendingWrite?.complete(Unit)
            } else {
                pendingWrite?.completeExceptionally(IllegalStateException("BLE write failed: $status"))
            }
        }

        @Deprecated("Deprecated in Java")
        override fun onCharacteristicChanged(
            activeGatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
            if (this@BleManager.gatt !== activeGatt) return
            @Suppress("DEPRECATION")
            handleNotification(characteristic.value ?: return)
        }

        override fun onCharacteristicChanged(
            activeGatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            if (this@BleManager.gatt !== activeGatt) return
            handleNotification(value)
        }
    }
}
