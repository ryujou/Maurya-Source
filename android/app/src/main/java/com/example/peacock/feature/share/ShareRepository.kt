package com.example.peacock.feature.share

import android.content.Context
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.time.Instant
import java.util.UUID

data class CreatedShare(
    val token: String,
    val shareUrl: String,
    val expiresAt: Instant,
    val blobSha256: String,
    val moderationVersion: String,
)

class ShareApiException(val status: Int, val code: String) : Exception(
    when (code) {
        "CONTENT_REJECTED" -> "内容包含不支持分享的敏感文本，请修改名称或源码"
        "SHARE_EXPIRED" -> "分享已过期"
        "SHARE_NOT_FOUND" -> "找不到该分享"
        "RATE_LIMITED" -> "操作过于频繁，请稍后再试"
        "STORAGE_LIMIT_REACHED" -> "服务器存储空间暂时不足"
        "UPLOADS_DISABLED" -> "分享上传暂不可用"
        else -> "分享服务请求失败（$code）"
    },
)

class ShareRepository(context: Context) {
    private val history = context.getSharedPreferences("share_import_history", Context.MODE_PRIVATE)

    fun create(envelope: ShareEnvelope): CreatedShare {
        val body = ShareEnvelopeCodec.encodeRequest(envelope)
        val response = request(
            path = "/maurya/api/share/v1/shares",
            method = "POST",
            headers = mapOf(
                "Content-Type" to MEDIA_TYPE,
                "Idempotency-Key" to UUID.randomUUID().toString(),
            ),
            body = body,
            maxBytes = 64 * 1024,
        )
        val root = JSONObject(response.toString(Charsets.UTF_8))
        return CreatedShare(
            token = parseToken(root.getString("token")),
            shareUrl = requireShareUrl(root.getString("shareUrl")),
            expiresAt = Instant.parse(root.getString("expiresAt")),
            blobSha256 = root.getString("blobSha256").also { require(HASH.matches(it)) },
            moderationVersion = root.getString("moderationVersion"),
        )
    }

    fun fetchMeta(rawToken: String): Pair<String, ShareMeta> {
        val token = parseToken(rawToken)
        val bytes = request("/maurya/api/share/v1/shares/$token/meta", maxBytes = 32 * 1024)
        val root = JSONObject(bytes.toString(Charsets.UTF_8))
        val meta = ShareMeta(
            kind = when (root.getString("kind")) {
                "effect" -> ShareKind.EFFECT
                "palette" -> ShareKind.PALETTE
                else -> error("不支持的分享类型")
            },
            createdAt = Instant.parse(root.getString("createdAt")),
            expiresAt = Instant.parse(root.getString("expiresAt")),
            expiresInSeconds = root.getLong("expiresInSeconds").also { require(it in 0..604800) },
            compressedBytes = root.getInt("compressedBytes").also {
                require(it in 1..ShareEnvelopeCodec.MAX_COMPRESSED_BYTES)
            },
            blobSha256 = root.getString("blobSha256").also { require(HASH.matches(it)) },
        )
        return token to meta
    }

    fun fetchForPreview(rawToken: String): PendingShareImport {
        val (token, meta) = fetchMeta(rawToken)
        val blob = request(
            "/maurya/api/share/v1/shares/$token/blob",
            maxBytes = ShareEnvelopeCodec.MAX_COMPRESSED_BYTES,
            expectedContentType = MEDIA_TYPE,
        )
        require(blob.size == meta.compressedBytes)
        val envelope = ShareEnvelopeCodec.decodeBlob(blob, meta.blobSha256)
        require(envelope.kind == meta.kind)
        return when (envelope.kind) {
            ShareKind.EFFECT -> PendingShareImport(token, envelope, effect = ShareEnvelopeCodec.previewEffect(envelope))
            ShareKind.PALETTE -> PendingShareImport(token, envelope, paletteAvatar = ShareEnvelopeCodec.paletteAvatar(envelope))
        }
    }

    fun wasImported(token: String): Boolean = history.contains(tokenHash(parseToken(token)))

    fun markImported(token: String, localId: String) {
        val key = tokenHash(parseToken(token))
        val order = history.getString(HISTORY_ORDER, "").orEmpty().split(',').filter { it.isNotBlank() }
            .filterNot { it == key }
        val next = (listOf(key) + order).take(256)
        val editor = history.edit().putString(key, localId).putString(HISTORY_ORDER, next.joinToString(","))
        order.drop(255).filterNot(next::contains).forEach(editor::remove)
        check(editor.commit())
    }

    private fun request(
        path: String,
        method: String = "GET",
        headers: Map<String, String> = emptyMap(),
        body: ByteArray? = null,
        maxBytes: Int,
        expectedContentType: String? = null,
    ): ByteArray {
        require(path.startsWith("/") && !path.contains(".."))
        val connection = (URL("$ORIGIN$path").openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 10_000
            readTimeout = 15_000
            instanceFollowRedirects = false
            useCaches = false
            setRequestProperty("Accept", expectedContentType ?: "application/json")
            headers.forEach(::setRequestProperty)
            if (body != null) {
                doOutput = true
                setFixedLengthStreamingMode(body.size)
                outputStream.use { it.write(body) }
            }
        }
        try {
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val bytes = stream?.use { readLimited(it, maxBytes) } ?: byteArrayOf()
            if (status !in 200..299) {
                val code = runCatching {
                    val error = JSONObject(bytes.toString(Charsets.UTF_8))
                    error.optJSONObject("error")?.getString("code") ?: error.getString("code")
                }
                    .getOrDefault("INVALID_REQUEST")
                throw ShareApiException(status, code)
            }
            expectedContentType?.let {
                require(connection.contentType?.substringBefore(';') == it) { "分享响应类型错误" }
            }
            return bytes
        } finally {
            connection.disconnect()
        }
    }

    private fun readLimited(input: java.io.InputStream, maxBytes: Int): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            require(output.size() + count <= maxBytes) { "分享响应过大" }
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    companion object {
        const val ORIGIN = "https://xtbang.top"
        const val MEDIA_TYPE = "application/vnd.maurya.share+gzip"
        private const val HISTORY_ORDER = "_order"
        private val TOKEN = Regex("[1-9A-HJ-NP-Za-km-z]{10}")
        private val SHORT_TOKEN = Regex("([1-9A-HJ-NP-Za-km-z]{5})-([1-9A-HJ-NP-Za-km-z]{5})")
        private val HASH = Regex("[0-9a-f]{64}")

        fun parseToken(raw: String): String {
            val candidate = raw.trim()
            if (TOKEN.matches(candidate)) return candidate
            SHORT_TOKEN.matchEntire(candidate)?.let { return it.groupValues[1] + it.groupValues[2] }
            return runCatching {
                val uri = URI(candidate)
                require(uri.scheme == "https" && uri.host == "xtbang.top" && uri.rawQuery == null && uri.rawFragment == null)
                val match = Regex("/maurya/s/([1-9A-HJ-NP-Za-km-z]{10})/?").matchEntire(uri.path)
                    ?: error("二维码不是Maurya分享链接")
                match.groupValues[1]
            }.getOrElse { throw IllegalArgumentException("分享码格式错误") }
        }

        fun shortCode(token: String): String = parseToken(token).let { "${it.take(5)}-${it.takeLast(5)}" }

        private fun requireShareUrl(value: String): String {
            val token = parseToken(value)
            val expected = "$ORIGIN/maurya/s/$token"
            require(value == expected)
            return expected
        }

        private fun tokenHash(token: String) = ShareEnvelopeCodec.sha256(token.toByteArray(Charsets.US_ASCII))
    }
}
