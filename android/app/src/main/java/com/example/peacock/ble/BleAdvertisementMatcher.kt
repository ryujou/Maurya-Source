package com.example.peacock.ble

import java.util.UUID

internal object BleAdvertisementMatcher {
    fun matches(
        filterMaurya: Boolean,
        name: String?,
        advertisedServices: Collection<UUID>,
    ): Boolean {
        if (!filterMaurya) return true

        return name
            ?.startsWith(prefix = "Maurya-", ignoreCase = true) == true ||
            UUID_FFE0 in advertisedServices
    }
}
