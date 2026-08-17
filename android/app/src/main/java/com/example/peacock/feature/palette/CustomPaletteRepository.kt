package com.example.peacock.feature.palette

import android.content.Context
import android.util.Base64
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID

data class CustomPaletteEntry(
    val id: String,
    val nameZh: String,
    val nameJa: String,
    val hex: String,
    val revision: Int,
    val avatarPath: String,
    val createdAt: String,
    val updatedAt: String,
) {
    fun displayName(useJapanese: Boolean): String =
        if (useJapanese) nameJa.ifBlank { nameZh } else nameZh.ifBlank { nameJa }
}

data class CustomPaletteState(
    val entries: List<CustomPaletteEntry> = emptyList(),
    val usedBytes: Long = 0,
    val limit: Int = 50,
    val error: String? = null,
)

class CustomPaletteRepository(context: Context) {
    private val root = File(context.filesDir, "custom_palette")
    private val avatars = File(root, "avatars")
    private val index = File(root, "index.json")
    private val mutableState = MutableStateFlow(CustomPaletteState())
    val state: StateFlow<CustomPaletteState> = mutableState

    init {
        root.mkdirs()
        avatars.mkdirs()
        reload()
    }

    @Synchronized
    fun save(
        existingId: String?,
        expectedRevision: Int,
        nameZh: String,
        nameJa: String,
        hex: String,
        avatarWebP: ByteArray,
    ): CustomPaletteEntry {
        require(nameZh.codePointCount(0, nameZh.length) <= 32)
        require(nameJa.codePointCount(0, nameJa.length) <= 32)
        require(nameZh.isNotBlank() || nameJa.isNotBlank())
        require(HEX.matches(hex))
        require(avatarWebP.size in 1..MAX_AVATAR_BYTES)
        require(isWebP96(avatarWebP))
        val current = mutableState.value.entries
        val old = existingId?.let { id -> current.firstOrNull { it.id == id } }
        if (existingId == null) require(current.size < MAX_ENTRIES)
        if (existingId != null) require(old != null && old.revision == expectedRevision) { "revision conflict" }
        val id = existingId ?: UUID.randomUUID().toString()
        val now = Instant.now().toString()
        val avatar = File(avatars, "$id.webp")
        atomicWrite(avatar, avatarWebP)
        val entry = CustomPaletteEntry(
            id = id,
            nameZh = nameZh.trim(),
            nameJa = nameJa.trim(),
            hex = hex.uppercase(),
            revision = (old?.revision ?: 0) + 1,
            avatarPath = avatar.absolutePath,
            createdAt = old?.createdAt ?: now,
            updatedAt = now,
        )
        val next = current.filterNot { it.id == id } + entry
        writeIndex(next)
        publish(next)
        return entry
    }

    @Synchronized
    fun delete(id: String, expectedRevision: Int) {
        val current = mutableState.value.entries
        val old = current.firstOrNull { it.id == id }
        require(old != null && old.revision == expectedRevision) { "revision conflict" }
        val next = current.filterNot { it.id == id }
        writeIndex(next)
        File(old.avatarPath).delete()
        publish(next)
    }

    @Synchronized
    fun exportBackup(): ByteArray {
        val entries = JSONArray()
        mutableState.value.entries.forEach { entry ->
            val bytes = File(entry.avatarPath).readBytes()
            entries.put(JSONObject().apply {
                put("id", entry.id)
                put("nameZh", entry.nameZh)
                put("nameJa", entry.nameJa)
                put("hex", entry.hex)
                put("createdAt", entry.createdAt)
                put("updatedAt", entry.updatedAt)
                put("avatarWebpBase64", Base64.encodeToString(bytes, Base64.NO_WRAP))
                put("avatarSha256", sha256(bytes))
            })
        }
        return JSONObject().apply {
            put("schemaVersion", 1)
            put("exportedAt", Instant.now().toString())
            put("entries", entries)
        }.toString(2).toByteArray(Charsets.UTF_8)
    }

    @Synchronized
    fun importBackup(bytes: ByteArray, overwrite: Boolean): Int {
        require(bytes.size <= 1024 * 1024)
        val rootJson = JSONObject(bytes.toString(Charsets.UTF_8))
        require(rootJson.getInt("schemaVersion") == 1)
        val imported = rootJson.getJSONArray("entries")
        require(imported.length() <= MAX_ENTRIES)
        var next = mutableState.value.entries
        var count = 0
        for (index in 0 until imported.length()) {
            val item = imported.getJSONObject(index)
            val id = item.getString("id")
            require(UUID.fromString(id).toString() == id.lowercase())
            val old = next.firstOrNull { it.id == id }
            if (old != null && !overwrite) continue
            require(next.size < MAX_ENTRIES || old != null)
            val avatarBytes = Base64.decode(item.getString("avatarWebpBase64"), Base64.DEFAULT)
            require(avatarBytes.size in 1..MAX_AVATAR_BYTES && isWebP96(avatarBytes))
            require(sha256(avatarBytes) == item.getString("avatarSha256").lowercase())
            val nameZh = item.optString("nameZh")
            val nameJa = item.optString("nameJa")
            val hex = item.getString("hex").uppercase()
            require(nameZh.isNotBlank() || nameJa.isNotBlank())
            require(HEX.matches(hex))
            val avatar = File(avatars, "$id.webp")
            atomicWrite(avatar, avatarBytes)
            val value = CustomPaletteEntry(
                id, nameZh, nameJa, hex, (old?.revision ?: 0) + 1, avatar.absolutePath,
                old?.createdAt ?: item.optString("createdAt", Instant.now().toString()),
                item.optString("updatedAt", Instant.now().toString()),
            )
            next = next.filterNot { it.id == id } + value
            count++
        }
        writeIndex(next)
        publish(next)
        return count
    }

    private fun reload() {
        runCatching {
            if (!index.exists()) emptyList() else parseEntries(JSONObject(index.readText()).getJSONArray("entries"))
        }.onSuccess(::publish).onFailure { mutableState.value = CustomPaletteState(error = it.message) }
        avatars.listFiles()?.filter { file -> mutableState.value.entries.none { it.avatarPath == file.absolutePath } }
            ?.forEach(File::delete)
    }

    private fun parseEntries(array: JSONArray): List<CustomPaletteEntry> = buildList {
        require(array.length() <= MAX_ENTRIES)
        for (i in 0 until array.length()) {
            val item = array.getJSONObject(i)
            val id = item.getString("id")
            val avatar = File(avatars, "$id.webp")
            if (!avatar.isFile) continue
            add(CustomPaletteEntry(id, item.optString("nameZh"), item.optString("nameJa"),
                item.getString("hex"), item.getInt("revision"), avatar.absolutePath,
                item.getString("createdAt"), item.getString("updatedAt")))
        }
    }

    private fun writeIndex(entries: List<CustomPaletteEntry>) {
        val array = JSONArray()
        entries.forEach { entry -> array.put(JSONObject().apply {
            put("id", entry.id); put("nameZh", entry.nameZh); put("nameJa", entry.nameJa)
            put("hex", entry.hex); put("revision", entry.revision)
            put("createdAt", entry.createdAt); put("updatedAt", entry.updatedAt)
        }) }
        atomicWrite(index, JSONObject().put("schemaVersion", 1).put("entries", array).toString().toByteArray())
    }

    private fun publish(entries: List<CustomPaletteEntry>) {
        mutableState.value = CustomPaletteState(entries.sortedByDescending { it.updatedAt },
            entries.sumOf { File(it.avatarPath).length() })
    }

    private fun atomicWrite(target: File, bytes: ByteArray) {
        val temporary = File(target.parentFile, "${target.name}.tmp")
        FileOutputStream(temporary).use { stream -> stream.write(bytes); stream.fd.sync() }
        check(temporary.renameTo(target) || (target.delete() && temporary.renameTo(target)))
    }

    companion object {
        const val MAX_ENTRIES = 50
        const val MAX_AVATAR_BYTES = 6144
        private val HEX = Regex("#[0-9A-Fa-f]{6}")

        internal fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
            .digest(bytes).joinToString("") { "%02x".format(it) }

        internal fun isWebP96(bytes: ByteArray): Boolean {
            if (bytes.size < 30 || bytes.copyOfRange(0, 4).toString(Charsets.US_ASCII) != "RIFF" ||
                bytes.copyOfRange(8, 12).toString(Charsets.US_ASCII) != "WEBP") return false
            val kind = bytes.copyOfRange(12, 16).toString(Charsets.US_ASCII)
            return when (kind) {
                "VP8X" -> 1 + le24(bytes, 24) == 96 && 1 + le24(bytes, 27) == 96
                "VP8L" -> bytes[20].toInt() and 0xff == 0x2f && run {
                    val bits = le32(bytes, 21); (bits and 0x3fff) + 1 == 96 && ((bits ushr 14) and 0x3fff) + 1 == 96
                }
                "VP8 " -> bytes[23].toInt() and 0xff == 0x9d && bytes[24].toInt() and 0xff == 1 &&
                    bytes[25].toInt() and 0xff == 0x2a && (le16(bytes, 26) and 0x3fff) == 96 && (le16(bytes, 28) and 0x3fff) == 96
                else -> false
            }
        }
        private fun le16(b: ByteArray, i: Int) = (b[i].toInt() and 0xff) or ((b[i + 1].toInt() and 0xff) shl 8)
        private fun le24(b: ByteArray, i: Int) = le16(b, i) or ((b[i + 2].toInt() and 0xff) shl 16)
        private fun le32(b: ByteArray, i: Int) = le24(b, i) or ((b[i + 3].toInt() and 0xff) shl 24)
    }
}
