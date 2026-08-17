package com.example.peacock.util

import android.Manifest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class PermissionUtilsTest {
    @Test
    fun android13AndLaterRequireOnlyBluetoothRuntimePermissions() {
        val permissions = requiredBlePermissions(33)

        assertArrayEquals(
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
            ),
            permissions,
        )
        assertFalse(Manifest.permission.NEARBY_WIFI_DEVICES in permissions)
    }

    @Test
    fun android12KeepsLocationCompatibilityPermissions() {
        assertArrayEquals(
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.ACCESS_COARSE_LOCATION,
                Manifest.permission.ACCESS_FINE_LOCATION,
            ),
            requiredBlePermissions(32),
        )
    }
}
