package com.example.peacock.feature.ota

import android.content.Context
import com.example.peacock.R
import com.example.peacock.ble.BleManager
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeout

enum class OtaStage {
    IDLE, CHECKING, DOWNLOADING, UPLOADING, VERIFYING,
    REBOOTING, RECONNECTING_BLE, SUCCESS, UP_TO_DATE, FAILED,
}

data class OtaUiState(
    val stage: OtaStage = OtaStage.IDLE,
    val progress: Float = 0f,
    val message: String = "",
    val installedVersion: String = "",
    val availableVersion: String = "",
    val canCancel: Boolean = false,
)

class OtaCoordinator(
    context: Context,
    private val ble: BleManager,
    private val repository: OtaRepository = OtaRepository(context),
) {
    private val context = context.applicationContext

    suspend fun run(
        deviceAddress: Int,
        update: (OtaUiState) -> Unit,
    ) {
        var image: CachedOtaImage? = null
        var installedVersion = ""
        var availableVersion = ""
        try {
            update(OtaUiState(OtaStage.CHECKING, message = text(R.string.ota_status_reading)))
            val info = OtaProtocol.parseInfo(ble.transceive(OtaProtocol.getInfoRequest(deviceAddress)))
            installedVersion = info.firmwareVersion
            check(info.layoutVersion >= OtaProtocol.layoutVersion) {
                text(R.string.ota_error_usb_migration)
            }
            val manifest = repository.fetchAndVerifyManifest(info.variant)
            availableVersion = manifest.versionName
            check(manifest.layoutVersion == info.layoutVersion) { text(R.string.ota_error_layout) }
            check(manifest.assetPackVersion == info.assetPackVersion) {
                text(R.string.ota_error_assets)
            }
            check((info.capabilities and OtaProtocol.capabilityBleOta) != 0) {
                text(R.string.ota_error_151_usb_bridge)
            }
            if (manifest.secureVersion <= info.secureVersion) {
                update(
                    OtaUiState(
                        OtaStage.UP_TO_DATE,
                        installedVersion = installedVersion,
                        availableVersion = availableVersion,
                        message = text(R.string.ota_already_latest),
                    ),
                )
                return
            }
            update(
                OtaUiState(
                    OtaStage.DOWNLOADING,
                    installedVersion = installedVersion,
                    availableVersion = availableVersion,
                    message = text(R.string.ota_status_downloading),
                    canCancel = true,
                ),
            )
            image = repository.download(manifest) { done, total ->
                update(
                    OtaUiState(
                        OtaStage.DOWNLOADING,
                        progress = ratio(done, total),
                        installedVersion = installedVersion,
                        availableVersion = availableVersion,
                        message = text(R.string.ota_download_progress, done / 1024, total / 1024),
                        canCancel = true,
                    ),
                )
            }
            update(
                OtaUiState(
                    OtaStage.UPLOADING,
                    installedVersion = installedVersion,
                    availableVersion = availableVersion,
                    message = text(R.string.ota_status_preparing_wifi),
                    canCancel = true,
                ),
            )
            OtaProtocol.parseBleBegin(
                ble.transceive(
                    OtaProtocol.bleBeginRequest(
                        deviceAddress,
                        image.file.length(),
                        manifest.sha256,
                    ),
                    timeoutMs = 8_000,
                ),
            )
            update(
                OtaUiState(
                    OtaStage.UPLOADING,
                    installedVersion = installedVersion,
                    availableVersion = availableVersion,
                    message = text(R.string.ota_status_uploading),
                    canCancel = true,
                ),
            )
            image.file.inputStream().buffered(OtaProtocol.bleChunkBytes).use { input ->
                val buffer = ByteArray(OtaProtocol.bleChunkBytes)
                var offset = 0
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    val chunk = if (count == buffer.size) buffer else buffer.copyOf(count)
                    val nextOffset = OtaProtocol.parseBleDataAck(
                        ble.transceive(
                            OtaProtocol.bleDataRequest(deviceAddress, offset, chunk),
                            timeoutMs = 3_000,
                        ),
                    )
                    check(nextOffset == offset + count) { "BLE OTA offset mismatch" }
                    offset = nextOffset
                    update(
                        OtaUiState(
                            OtaStage.UPLOADING,
                            progress = ratio(offset.toLong(), image.file.length()),
                            installedVersion = installedVersion,
                            availableVersion = availableVersion,
                            canCancel = true,
                            message = text(
                                R.string.ota_upload_progress,
                                offset / 1024,
                                image.file.length() / 1024,
                            ),
                        ),
                    )
                }
            }
            update(
                OtaUiState(
                    OtaStage.VERIFYING,
                    progress = 1f,
                    installedVersion = installedVersion,
                    availableVersion = availableVersion,
                    message = text(R.string.ota_status_verified),
                ),
            )
            withTimeout(45_000) {
                while (true) {
                    val status = OtaProtocol.parseBleStatus(
                        ble.transceive(
                            OtaProtocol.bleStatusRequest(deviceAddress),
                            timeoutMs = 3_000,
                        ),
                    )
                    when (status.state) {
                        OtaProtocol.stateVerified -> break
                        OtaProtocol.stateFailed ->
                            error("设备验证失败，错误码 ${status.errorCode}")
                    }
                    delay(300)
                }
            }
            OtaProtocol.parseBleCommit(
                ble.transceive(
                    OtaProtocol.bleCommitRequest(deviceAddress),
                    timeoutMs = 5_000,
                ),
            )
            update(
                OtaUiState(
                    OtaStage.REBOOTING,
                    progress = 1f,
                    installedVersion = installedVersion,
                    availableVersion = availableVersion,
                    message = text(R.string.ota_status_rebooting),
                ),
            )
            delay(2_500)
            update(
                OtaUiState(
                    OtaStage.RECONNECTING_BLE,
                    progress = 1f,
                    installedVersion = installedVersion,
                    availableVersion = availableVersion,
                    message = text(R.string.ota_status_reconnecting),
                ),
            )
            check(ble.reconnectUntilReady()) { text(R.string.ota_error_reconnect_timeout) }
            val updated = withTimeout(10_000) {
                var lastError: Throwable? = null
                while (true) {
                    try {
                        return@withTimeout OtaProtocol.parseInfo(
                            ble.transceive(
                                OtaProtocol.getInfoRequest(deviceAddress),
                                timeoutMs = 3_000,
                            ),
                        )
                    } catch (error: Throwable) {
                        lastError = error
                        delay(350)
                        if (!ble.session.value.isReady) {
                            ble.reconnectUntilReady(timeoutMs = 3_000)
                        }
                    }
                }
                @Suppress("UNREACHABLE_CODE")
                throw lastError ?: IllegalStateException("firmware version unavailable")
            }
            check(updated.firmwareVersion == manifest.versionName) {
                text(R.string.ota_error_version_unchanged, updated.firmwareVersion)
            }
            repository.delete(image)
            update(
                OtaUiState(
                    OtaStage.SUCCESS,
                    progress = 1f,
                    installedVersion = updated.firmwareVersion,
                    availableVersion = manifest.versionName,
                    message = text(R.string.ota_status_success),
                ),
            )
        } catch (error: Throwable) {
            update(
                OtaUiState(
                    OtaStage.FAILED,
                    installedVersion = installedVersion,
                    availableVersion = availableVersion,
                    message = error.message ?: text(R.string.ota_status_failed),
                ),
            )
            throw error
        }
    }

    suspend fun readInstalledVersion(deviceAddress: Int): String =
        OtaProtocol.parseInfo(
            ble.transceive(OtaProtocol.getInfoRequest(deviceAddress)),
        ).firmwareVersion

    suspend fun cancel(deviceAddress: Int) {
        runCatching {
            OtaProtocol.parseBleCancel(
                ble.transceive(OtaProtocol.bleCancelRequest(deviceAddress)),
            )
        }
    }

    private fun ratio(done: Long, total: Long) =
        if (total <= 0L) 0f else (done.toDouble() / total).toFloat().coerceIn(0f, 1f)

    private fun text(resource: Int, vararg arguments: Any): String =
        context.getString(resource, *arguments)
}
