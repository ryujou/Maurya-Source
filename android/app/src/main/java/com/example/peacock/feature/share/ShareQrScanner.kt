package com.example.peacock.feature.share

import android.annotation.SuppressLint
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

@Composable
fun ShareQrScanner(
    onResult: (String) -> Unit,
    onError: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val previewView = remember {
        PreviewView(context).apply {
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
    }
    val callback = remember(onResult) { onResult }

    DisposableEffect(previewView, lifecycleOwner) {
        val executor = Executors.newSingleThreadExecutor()
        val active = AtomicBoolean(true)
        var provider: ProcessCameraProvider? = null
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            if (!active.get()) return@addListener
            runCatching {
                provider = future.get()
                val preview = Preview.Builder().build().also {
                    it.surfaceProvider = previewView.surfaceProvider
                }
                val analysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                val reader = qrReader()
                analysis.setAnalyzer(executor) { image ->
                    val decoded = if (active.get()) decodeQr(image, reader) else null
                    image.close()
                    if (decoded != null && active.compareAndSet(true, false)) {
                        ContextCompat.getMainExecutor(context).execute { callback(decoded) }
                    }
                }
                provider?.unbindAll()
                provider?.bindToLifecycle(
                    lifecycleOwner,
                    CameraSelector.DEFAULT_BACK_CAMERA,
                    preview,
                    analysis,
                )
            }.onFailure {
                ContextCompat.getMainExecutor(context).execute { onError("无法启动相机扫码") }
            }
        }, ContextCompat.getMainExecutor(context))

        onDispose {
            active.set(false)
            provider?.unbindAll()
            executor.shutdownNow()
        }
    }

    AndroidView(factory = { previewView }, modifier = modifier)
}

@SuppressLint("UnsafeOptInUsageError")
private fun decodeQr(image: ImageProxy, reader: MultiFormatReader): String? = runCatching {
    val width = image.width
    val height = image.height
    val plane = image.planes.first()
    val buffer = plane.buffer
    val bytes = ByteArray(width * height)
    for (row in 0 until height) {
        val rowStart = row * plane.rowStride
        for (column in 0 until width) {
            bytes[row * width + column] = buffer.get(rowStart + column * plane.pixelStride)
        }
    }
    val source = PlanarYUVLuminanceSource(bytes, width, height, 0, 0, width, height, false)
    reader.decodeWithState(BinaryBitmap(HybridBinarizer(source))).text
}.also { reader.reset() }.getOrNull()

private fun qrReader() = MultiFormatReader().apply {
    setHints(
        mapOf(
            DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE),
            DecodeHintType.TRY_HARDER to true,
            DecodeHintType.CHARACTER_SET to "UTF-8",
        ),
    )
}
