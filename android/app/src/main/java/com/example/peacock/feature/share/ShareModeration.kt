package com.example.peacock.feature.share

import java.text.Normalizer
import java.util.Locale

/**
 * Fast, deliberately incomplete client-side precheck. The server remains authoritative and
 * performs the full pinned-list moderation pass before accepting a blob.
 */
object ShareModeration {
    sealed interface Result {
        data object Accepted : Result
        data object Rejected : Result
    }

    private val zeroWidth = Regex("[\\u200B-\\u200F\\u2060\\uFE00-\\uFE0F\\uFEFF]")
    private val separators = Regex("[\\s\\p{P}\\p{S}_]+")
    private val trie = Trie(
        listOf(
            "六四事件", "天安门事件", "八九民运", "文化大革命", "反革命",
            "推翻共产党", "打倒共产党", "共产党下台", "中国共产党下台",
            "习近平下台", "习包子", "毛腊肉", "法轮功", "藏独", "疆独", "台独建国",
            "民主中国阵线", "中国民主党", "新唐人电视台", "大纪元时报",
        ).map(::normalise),
    )

    fun check(envelope: ShareEnvelope): Result {
        val text = buildString {
            append(envelope.displayName.zh).append('\n').append(envelope.displayName.ja)
            if (envelope.kind == ShareKind.EFFECT) {
                append('\n').append(envelope.payload.optString("source"))
            }
        }
        val normalised = normalise(text)
        val compact = normalised.replace(separators, "")
        return if (trie.contains(normalised) || trie.contains(compact)) Result.Rejected
        else Result.Accepted
    }

    private fun normalise(value: String): String {
        val base = Normalizer.normalize(value, Normalizer.Form.NFKC)
            .lowercase(Locale.ROOT)
            .replace(zeroWidth, "")
        return buildString {
            base.codePoints().forEach { codePoint ->
                if (codePoint !in 0xE0100..0xE01EF &&
                    Character.getType(codePoint) != Character.CONTROL.toInt()) {
                    appendCodePoint(codePoint)
                }
            }
        }
    }

    private class Trie(words: List<String>) {
        private class Node {
            val children = mutableMapOf<Char, Node>()
            var terminal = false
        }

        private val root = Node()

        init {
            words.filter(String::isNotBlank).forEach { word ->
                var node = root
                word.forEach { character -> node = node.children.getOrPut(character, ::Node) }
                node.terminal = true
            }
        }

        fun contains(text: String): Boolean {
            for (start in text.indices) {
                var node = root
                for (index in start until text.length) {
                    node = node.children[text[index]] ?: break
                    if (node.terminal) return true
                }
            }
            return false
        }
    }
}
