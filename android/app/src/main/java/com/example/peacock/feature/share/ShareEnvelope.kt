package com.example.peacock.feature.share

import android.util.Base64
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.example.peacock.feature.effects.EffectProgram
import com.example.peacock.feature.effects.EffectProgramCompiler
import com.example.peacock.feature.effects.EffectProgramSchemas
import com.example.peacock.feature.effects.EffectSourceKind
import com.example.peacock.feature.palette.CustomPaletteEntry
import com.example.peacock.feature.palette.CustomPaletteRepository
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import java.text.Normalizer
import java.time.Instant
import java.util.UUID
import java.util.zip.CRC32
import java.util.zip.GZIPOutputStream
import java.util.zip.Inflater

enum class ShareKind(val wireName: String) { EFFECT("effect"), PALETTE("palette") }

data class ShareDisplayName(val zh: String, val ja: String)

data class ShareEnvelope(
    val kind: ShareKind,
    val displayName: ShareDisplayName,
    val payload: JSONObject,
    val contentHash: String,
    val createdAt: Instant? = null,
)

data class ShareMeta(
    val kind: ShareKind,
    val createdAt: Instant,
    val expiresAt: Instant,
    val expiresInSeconds: Long,
    val compressedBytes: Int,
    val blobSha256: String,
)

data class PendingShareImport(
    val token: String,
    val envelope: ShareEnvelope,
    val effect: EffectProgram? = null,
    val paletteAvatar: ByteArray? = null,
)

object ShareEnvelopeCodec {
    const val MAX_COMPRESSED_BYTES = 256 * 1024
    const val MAX_UNCOMPRESSED_BYTES = 2 * 1024 * 1024
    const val MAX_SOURCE_BYTES = 256 * 1024
    const val JSON_MAX_DEPTH = 32
    private val hashPattern = Regex("[0-9a-f]{64}")
    private val hexPattern = Regex("#[0-9A-F]{6}")
    private val forbiddenText = Regex("[\\u0000-\\u001F\\u007F\\u202A-\\u202E\\u2066-\\u2069]")
    private val forbiddenSourceText = Regex("[\\u0000-\\u0008\\u000B\\u000C\\u000E-\\u001F\\u007F\\u202A-\\u202E\\u2066-\\u2069]")

    fun forEffect(program: EffectProgram): ShareEnvelope {
        EffectProgramCompiler.compile(program)
        val source = when (program.sourceKind) {
            EffectSourceKind.BLOCKS -> program.workspaceJson
            EffectSourceKind.SCRIPT -> program.scriptSource
        }
        require(source.isNotBlank() && source.toByteArray(Charsets.UTF_8).size <= MAX_SOURCE_BYTES)
        if (program.sourceKind == EffectSourceKind.BLOCKS) StrictJson.validate(source, JSON_MAX_DEPTH)
        val payload = JSONObject()
            .put("sourceKind", program.sourceKind.name.lowercase())
            .put("editorSchema", EffectProgramSchemas.EDITOR)
            .put("programSchema", EffectProgramSchemas.PROGRAM)
            .put("source", source)
        return build(ShareKind.EFFECT, program.nameZh, program.nameJa, payload)
    }

    fun forPalette(entry: CustomPaletteEntry): ShareEnvelope {
        val avatar = normaliseAvatarWebp(java.io.File(entry.avatarPath).readBytes())
        require(avatar.size in 1..CustomPaletteRepository.MAX_AVATAR_BYTES)
        require(CustomPaletteRepository.isWebP96(avatar))
        val payload = JSONObject()
            .put("hex", entry.hex.uppercase())
            .put("avatarWebpBase64", Base64.encodeToString(avatar, Base64.NO_WRAP))
            .put("avatarSha256", sha256(avatar))
        return build(ShareKind.PALETTE, entry.nameZh, entry.nameJa, payload)
    }

    fun encodeRequest(envelope: ShareEnvelope): ByteArray = gzip(canonicalEnvelope(envelope, includeCreatedAt = false))

    fun decodeBlob(compressed: ByteArray, expectedSha256: String): ShareEnvelope {
        require(compressed.size <= MAX_COMPRESSED_BYTES) { "分享数据过大" }
        require(hashPattern.matches(expectedSha256) && sha256(compressed) == expectedSha256) {
            "分享数据校验失败"
        }
        val json = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(gunzip(compressed)))
            .toString()
        StrictJson.validate(json, JSON_MAX_DEPTH)
        val root = JSONObject(json)
        requireKeys(root, setOf("schema", "kind", "displayName", "payload", "contentHash", "createdAt"))
        require(exactInt(root, "schema") == 1)
        val kind = parseKind(root.getString("kind"))
        val names = root.getJSONObject("displayName")
        requireKeys(names, setOf("zh", "ja"))
        val displayName = normaliseNames(kind, names.getString("zh"), names.getString("ja"))
        val payload = root.getJSONObject("payload")
        validatePayload(kind, payload)
        val suppliedHash = root.getString("contentHash")
        require(hashPattern.matches(suppliedHash))
        val calculated = computeContentHash(kind, displayName, payload)
        require(MessageDigest.isEqual(suppliedHash.toByteArray(), calculated.toByteArray())) {
            "分享内容校验失败"
        }
        return ShareEnvelope(kind, displayName, payload, suppliedHash, Instant.parse(root.getString("createdAt")))
    }

    fun previewEffect(envelope: ShareEnvelope): EffectProgram {
        require(envelope.kind == ShareKind.EFFECT)
        val sourceKind = when (envelope.payload.getString("sourceKind")) {
            "blocks" -> EffectSourceKind.BLOCKS
            "script" -> EffectSourceKind.SCRIPT
            else -> error("不支持的灯效源码")
        }
        val now = System.currentTimeMillis()
        val source = envelope.payload.getString("source")
        val candidate = EffectProgram(
            id = UUID.randomUUID().toString(),
            nameZh = envelope.displayName.zh,
            nameJa = envelope.displayName.ja,
            workspaceJson = if (sourceKind == EffectSourceKind.BLOCKS) source else "",
            astJson = "",
            astSha256 = "",
            blockCount = 0,
            estimatedDurationMs = null,
            createdAt = now,
            updatedAt = now,
            editorSchema = EffectProgramSchemas.EDITOR,
            programSchema = EffectProgramSchemas.PROGRAM,
            sourceKind = sourceKind,
            scriptSource = if (sourceKind == EffectSourceKind.SCRIPT) source else "",
        )
        return EffectProgramCompiler.normalise(candidate)
    }

    fun paletteAvatar(envelope: ShareEnvelope): ByteArray {
        require(envelope.kind == ShareKind.PALETTE)
        val encoded = envelope.payload.getString("avatarWebpBase64")
        val bytes = strictBase64(encoded)
        require(bytes.size in 1..CustomPaletteRepository.MAX_AVATAR_BYTES)
        require(CustomPaletteRepository.isWebP96(bytes))
        require(sha256(bytes) == envelope.payload.getString("avatarSha256"))
        return normaliseAvatarWebp(bytes)
    }

    fun canonicalEnvelope(envelope: ShareEnvelope, includeCreatedAt: Boolean): ByteArray {
        val name = "{\"ja\":${quote(envelope.displayName.ja)},\"zh\":${quote(envelope.displayName.zh)}}"
        val fields = mutableListOf(
            "\"contentHash\":${quote(envelope.contentHash)}",
        )
        if (includeCreatedAt) fields += "\"createdAt\":${quote(requireNotNull(envelope.createdAt).toString())}"
        fields += listOf(
            "\"displayName\":$name",
            "\"kind\":${quote(envelope.kind.wireName)}",
            "\"payload\":${canonicalPayload(envelope.kind, envelope.payload)}",
            "\"schema\":1",
        )
        return "{${fields.sorted().joinToString(",")}}".toByteArray(Charsets.UTF_8)
    }

    private fun build(kind: ShareKind, zh: String, ja: String, payload: JSONObject): ShareEnvelope {
        val names = normaliseNames(kind, zh, ja)
        validatePayload(kind, payload)
        return ShareEnvelope(kind, names, payload, computeContentHash(kind, names, payload))
    }

    internal fun computeContentHash(kind: ShareKind, names: ShareDisplayName, payload: JSONObject): String {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update("maurya-share-v1\u0000".toByteArray(Charsets.UTF_8))
        listOf(
            kind.wireName.toByteArray(Charsets.UTF_8),
            names.zh.toByteArray(Charsets.UTF_8),
            names.ja.toByteArray(Charsets.UTF_8),
            canonicalPayload(kind, payload).toByteArray(Charsets.UTF_8),
        ).forEach { bytes ->
            digest.update(ByteBuffer.allocate(4).putInt(bytes.size).array())
            digest.update(bytes)
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun canonicalPayload(kind: ShareKind, payload: JSONObject): String = when (kind) {
        ShareKind.EFFECT -> "{" + listOf(
            "\"editorSchema\":${exactInt(payload, "editorSchema")}",
            "\"programSchema\":${exactInt(payload, "programSchema")}",
            "\"source\":${quote(payload.getString("source"))}",
            "\"sourceKind\":${quote(payload.getString("sourceKind"))}",
        ).sorted().joinToString(",") + "}"
        ShareKind.PALETTE -> "{" + listOf(
            "\"avatarSha256\":${quote(payload.getString("avatarSha256"))}",
            "\"avatarWebpBase64\":${quote(payload.getString("avatarWebpBase64"))}",
            "\"hex\":${quote(payload.getString("hex"))}",
        ).sorted().joinToString(",") + "}"
    }

    private fun validatePayload(kind: ShareKind, payload: JSONObject) {
        when (kind) {
            ShareKind.EFFECT -> {
                requireKeys(payload, setOf("sourceKind", "editorSchema", "programSchema", "source"))
                require(payload.getString("sourceKind") in setOf("blocks", "script"))
                require(exactInt(payload, "editorSchema") == EffectProgramSchemas.EDITOR)
                require(exactInt(payload, "programSchema") == EffectProgramSchemas.PROGRAM)
                val source = payload.getString("source")
                require(source.isNotBlank() && source.toByteArray().size <= MAX_SOURCE_BYTES)
                rejectForbiddenSource(source)
                if (payload.getString("sourceKind") == "blocks") StrictJson.validate(source, JSON_MAX_DEPTH)
            }
            ShareKind.PALETTE -> {
                requireKeys(payload, setOf("hex", "avatarWebpBase64", "avatarSha256"))
                require(hexPattern.matches(payload.getString("hex")))
                val avatar = strictBase64(payload.getString("avatarWebpBase64"))
                require(avatar.size in 1..CustomPaletteRepository.MAX_AVATAR_BYTES)
                require(CustomPaletteRepository.isWebP96(avatar))
                require(hashPattern.matches(payload.getString("avatarSha256")))
                require(sha256(avatar) == payload.getString("avatarSha256"))
            }
        }
    }

    private fun normaliseNames(kind: ShareKind, zh: String, ja: String): ShareDisplayName {
        val limit = if (kind == ShareKind.EFFECT) 64 else 32
        fun one(value: String): String = Normalizer.normalize(value.trim(), Normalizer.Form.NFC).also {
            require(it.codePointCount(0, it.length) <= limit)
            rejectForbidden(it)
        }
        return ShareDisplayName(one(zh), one(ja)).also { require(it.zh.isNotBlank() || it.ja.isNotBlank()) }
    }

    private fun rejectForbidden(value: String) = require(!forbiddenText.containsMatchIn(value)) { "文本包含不支持的控制字符" }

    private fun rejectForbiddenSource(value: String) =
        require(!forbiddenSourceText.containsMatchIn(value)) { "源码包含不支持的控制字符" }

    private fun requireKeys(value: JSONObject, expected: Set<String>) {
        val actual = value.keys().asSequence().toSet()
        require(actual == expected) { "分享结构包含未知或缺失字段" }
    }

    private fun exactInt(value: JSONObject, key: String): Int {
        val raw = value.get(key)
        require(raw is Int || raw is Long) { "$key 必须是整数" }
        val number = (raw as Number).toLong()
        require(number in Int.MIN_VALUE..Int.MAX_VALUE)
        return number.toInt()
    }

    private fun strictBase64(value: String): ByteArray {
        require(value.isNotEmpty() && value.length % 4 == 0)
        require(Regex("(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?").matches(value))
        return Base64.decode(value, Base64.NO_WRAP).also {
            require(Base64.encodeToString(it, Base64.NO_WRAP) == value)
        }
    }

    private fun normaliseAvatarWebp(source: ByteArray): ByteArray {
        val bitmap = BitmapFactory.decodeByteArray(source, 0, source.size)
            ?: error("头像不是可解码的WebP")
        require(bitmap.width == 96 && bitmap.height == 96) { "头像必须是96×96" }
        return try {
            for (quality in listOf(90, 82, 74, 66, 58, 50)) {
                val output = ByteArrayOutputStream()
                require(bitmap.compress(Bitmap.CompressFormat.WEBP_LOSSY, quality, output))
                val bytes = output.toByteArray()
                if (bytes.size in 1..CustomPaletteRepository.MAX_AVATAR_BYTES) return bytes
            }
            error("头像重新编码后仍超过6144字节")
        } finally {
            bitmap.recycle()
        }
    }

    private fun parseKind(value: String) = ShareKind.entries.firstOrNull { it.wireName == value }
        ?: error("不支持的分享类型")

    /** Matches Python json.dumps(..., ensure_ascii=False) string escaping. */
    private fun quote(value: String): String = buildString(value.length + 2) {
        append('"')
        var index = 0
        while (index < value.length) {
            val character = value[index]
            when (character) {
                '"' -> append("\\\"")
                '\\' -> append("\\\\")
                '\b' -> append("\\b")
                '\u000c' -> append("\\f")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> when {
                    character.code < 0x20 -> append("\\u%04x".format(character.code))
                    character.isHighSurrogate() -> {
                        require(index + 1 < value.length && value[index + 1].isLowSurrogate()) {
                            "文本包含无效Unicode代理项"
                        }
                        append(character).append(value[++index])
                    }
                    character.isLowSurrogate() -> error("文本包含无效Unicode代理项")
                    else -> append(character)
                }
            }
            index++
        }
        append('"')
    }

    private fun gzip(bytes: ByteArray): ByteArray = ByteArrayOutputStream().use { output ->
        GZIPOutputStream(output).use { it.write(bytes) }
        output.toByteArray().also { require(it.size <= MAX_COMPRESSED_BYTES) }
    }

    private fun gunzip(bytes: ByteArray): ByteArray {
        require(bytes.size >= 18 && bytes[0] == 0x1f.toByte() && bytes[1] == 0x8b.toByte() && bytes[2] == 8.toByte())
        val flags = bytes[3].toInt() and 0xff
        require(flags and 0xe0 == 0) { "gzip标志无效" }
        var offset = 10
        fun need(count: Int) = require(offset + count <= bytes.size - 8) { "gzip头不完整" }
        if (flags and 0x04 != 0) {
            need(2); val length = (bytes[offset].toInt() and 0xff) or ((bytes[offset + 1].toInt() and 0xff) shl 8)
            offset += 2; need(length); offset += length
        }
        fun skipZeroTerminated() { while (true) { need(1); if (bytes[offset++].toInt() == 0) break } }
        if (flags and 0x08 != 0) skipZeroTerminated()
        if (flags and 0x10 != 0) skipZeroTerminated()
        if (flags and 0x02 != 0) { need(2); offset += 2 }

        val inflater = Inflater(true)
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        try {
            inflater.setInput(bytes, offset, bytes.size - offset)
            while (!inflater.finished()) {
                val count = inflater.inflate(buffer)
                if (count == 0) require(!inflater.needsDictionary() && !inflater.needsInput()) { "gzip数据不完整" }
                require(output.size() + count <= MAX_UNCOMPRESSED_BYTES) { "分享数据解压后过大" }
                output.write(buffer, 0, count)
            }
            val trailer = offset + inflater.totalIn
            require(trailer + 8 == bytes.size) { "只允许单个完整gzip成员" }
            val expanded = output.toByteArray()
            fun le32(at: Int): Long = (0..3).fold(0L) { result, index ->
                result or ((bytes[at + index].toLong() and 0xff) shl (8 * index))
            }
            val crc = CRC32().apply { update(expanded) }.value
            require(
                le32(trailer) == crc &&
                    le32(trailer + 4) == (expanded.size.toLong() and 0xffffffffL),
            ) {
                "gzip校验失败"
            }
            return expanded
        } finally {
            inflater.end()
        }
    }

    fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes).joinToString("") { "%02x".format(it) }
}

/** Lightweight structural pass used before org.json so duplicate keys and excessive nesting fail closed. */
internal object StrictJson {
    fun validate(text: String, maxDepth: Int) {
        val parser = Parser(text, maxDepth)
        parser.value(0)
        parser.space()
        require(parser.end()) { "JSON尾部包含额外内容" }
    }

    private class Parser(private val text: String, private val maxDepth: Int) {
        private var index = 0
        fun end() = index == text.length
        fun space() { while (index < text.length && text[index].isWhitespace()) index++ }
        fun value(depth: Int) {
            require(depth <= maxDepth) { "JSON嵌套超过限制" }
            space(); require(index < text.length)
            when (text[index]) {
                '{' -> obj(depth + 1)
                '[' -> array(depth + 1)
                '"' -> string()
                't' -> literal("true")
                'f' -> literal("false")
                'n' -> literal("null")
                else -> number()
            }
        }
        private fun obj(depth: Int) {
            index++; space(); val keys = mutableSetOf<String>()
            if (take('}')) return
            while (true) {
                space(); require(peek() == '"'); val key = string(); require(keys.add(key)) { "JSON包含重复字段" }
                space(); require(take(':')); value(depth); space()
                if (take('}')) return
                require(take(','))
            }
        }
        private fun array(depth: Int) {
            index++; space(); if (take(']')) return
            while (true) { value(depth); space(); if (take(']')) return; require(take(',')) }
        }
        private fun string(): String {
            require(take('"')); val out = StringBuilder()
            while (index < text.length) {
                val c = text[index++]
                when {
                    c == '"' -> return out.toString()
                    c == '\\' -> {
                        require(index < text.length); val escaped = text[index++]
                        if (escaped == 'u') {
                            require(index + 4 <= text.length)
                            val hex = text.substring(index, index + 4)
                            require(hex.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' })
                            out.append(hex.toInt(16).toChar()); index += 4
                        } else { require(escaped in "\"\\/bfnrt"); out.append(' ') }
                    }
                    c.code < 0x20 -> error("JSON字符串含控制字符")
                    else -> out.append(c)
                }
            }
            error("JSON字符串未结束")
        }
        private fun number() {
            val start = index
            if (peek() == '-') index++
            require(index < text.length && text[index].isDigit())
            if (text[index] == '0') index++ else while (index < text.length && text[index].isDigit()) index++
            if (peek() == '.') { index++; require(index < text.length && text[index].isDigit()); while (index < text.length && text[index].isDigit()) index++ }
            if (peek() == 'e' || peek() == 'E') {
                index++; if (peek() == '+' || peek() == '-') index++
                require(index < text.length && text[index].isDigit()); while (index < text.length && text[index].isDigit()) index++
            }
            require(index > start)
        }
        private fun literal(value: String) { require(text.startsWith(value, index)); index += value.length }
        private fun take(c: Char): Boolean = if (peek() == c) { index++; true } else false
        private fun peek(): Char = if (index < text.length) text[index] else '\u0000'
    }
}
