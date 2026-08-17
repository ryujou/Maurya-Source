package com.example.peacock.feature.ota

import android.content.Context
import android.util.Base64
import com.example.peacock.BuildConfig
import com.example.peacock.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.X509EncodedKeySpec

data class OtaManifest(
    val variant: String,
    val layoutVersion: Int,
    val assetPackVersion: Int,
    val versionName: String,
    val secureVersion: Int,
    val size: Long,
    val sha256: String,
    val downloadUrl: String,
    val minimumAppVersion: Int,
)

data class CachedOtaImage(val manifest: OtaManifest, val file: File)

class OtaRepository(private val context: Context) {
    private val cacheDir = File(context.noBackupFilesDir, "ota").apply { mkdirs() }

    suspend fun fetchAndVerifyManifest(variant: String): OtaManifest = withContext(Dispatchers.IO) {
        val channel = if (variant == "ja") "ja" else "multilingual"
        val base = "https://xtbang.top/maurya/ota/stable/$channel"
        val bytes = getBytes("$base/manifest.json", noCache = true)
        val signature = getBytes("$base/manifest.sig", noCache = true)
        check(verifyManifest(bytes, signature)) { "固件清单签名无效" }
        parseManifest(JSONObject(bytes.toString(Charsets.UTF_8)))
    }

    suspend fun download(
        manifest: OtaManifest,
        onProgress: (Long, Long) -> Unit,
    ): CachedOtaImage = withContext(Dispatchers.IO) {
        check(manifest.minimumAppVersion <= BuildConfig.VERSION_CODE) {
            "请先升级 Maurya APP"
        }
        val finalFile = File(cacheDir, "${manifest.variant}-${manifest.versionName}.bin")
        if (finalFile.isFile && finalFile.length() == manifest.size &&
            sha256(finalFile).equals(manifest.sha256, ignoreCase = true)
        ) {
            return@withContext CachedOtaImage(manifest, finalFile)
        }
        val part = File(finalFile.path + ".part")
        var offset = part.takeIf(File::isFile)?.length()?.coerceAtMost(manifest.size) ?: 0L
        if (offset == manifest.size) offset = 0L
        val connection = URL(manifest.downloadUrl).openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 20_000
        connection.setRequestProperty("Accept-Encoding", "identity")
        if (offset > 0L) connection.setRequestProperty("Range", "bytes=$offset-")
        connection.connect()
        val append = offset > 0L && connection.responseCode == HttpURLConnection.HTTP_PARTIAL
        if (!append) offset = 0L
        check(connection.responseCode in 200..299) { "下载失败 HTTP ${connection.responseCode}" }
        java.io.FileOutputStream(part, append).buffered().use { output ->
            connection.inputStream.buffered().use { input ->
                val buffer = ByteArray(64 * 1024)
                var done = offset
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    output.write(buffer, 0, read)
                    done += read
                    onProgress(done, manifest.size)
                }
            }
        }
        connection.disconnect()
        check(part.length() == manifest.size) { "固件大小不匹配" }
        check(sha256(part).equals(manifest.sha256, ignoreCase = true)) { "固件 SHA-256 不匹配" }
        if (finalFile.exists()) check(finalFile.delete())
        check(part.renameTo(finalFile)) { "无法提交固件缓存" }
        CachedOtaImage(manifest, finalFile)
    }

    fun delete(image: CachedOtaImage) {
        image.file.delete()
    }

    private fun getBytes(url: String, noCache: Boolean): ByteArray {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 12_000
        connection.readTimeout = 12_000
        if (noCache) connection.setRequestProperty("Cache-Control", "no-cache")
        check(connection.responseCode == 200) { "HTTP ${connection.responseCode}" }
        return connection.inputStream.use { it.readBytes() }.also { connection.disconnect() }
    }

    private fun verifyManifest(data: ByteArray, detached: ByteArray): Boolean {
        val pem = context.resources.openRawResource(R.raw.maurya_ota_public_key)
            .bufferedReader().use { it.readText() }
        val encoded = pem.lineSequence().filterNot { it.startsWith("-----") }.joinToString("")
        val key = KeyFactory.getInstance("RSA").generatePublic(
            X509EncodedKeySpec(Base64.decode(encoded, Base64.DEFAULT)),
        )
        val signatureBytes = runCatching {
            Base64.decode(detached.toString(Charsets.US_ASCII).trim(), Base64.DEFAULT)
        }.getOrElse { detached }
        return Signature.getInstance("SHA256withRSA").run {
            initVerify(key)
            update(data)
            verify(signatureBytes)
        }
    }

    private fun parseManifest(json: JSONObject) = OtaManifest(
        variant = json.getString("variant"),
        layoutVersion = json.getInt("layoutVersion"),
        assetPackVersion = json.getInt("assetPackVersion"),
        versionName = json.getString("versionName"),
        secureVersion = json.getInt("secureVersion"),
        size = json.getLong("size"),
        sha256 = json.getString("sha256").lowercase(),
        downloadUrl = json.getString("downloadUrl"),
        minimumAppVersion = json.optInt("minimumAppVersion", 307),
    )

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
