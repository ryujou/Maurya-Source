package com.example.peacock.ble

import android.bluetooth.BluetoothDevice

data class BleDeviceItem(
    val name: String,
    val address: String,
    val rssi: Int,
    val device: BluetoothDevice,
)

data class BleSessionState(
    val isScanning: Boolean = false,
    val selectedDevice: BleDeviceItem? = null,
    val connectionText: String = "",
    val servicesText: String = "",
    val negotiatedMtu: Int = 23,
    val isReady: Boolean = false,
)
