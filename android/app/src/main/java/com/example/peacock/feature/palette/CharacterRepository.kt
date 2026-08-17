package com.example.peacock.feature.palette

import android.content.Context
import org.json.JSONObject

object CharacterRepository {
    fun loadCatalog(context: Context): PaletteCatalog {
        return try {
            context.assets.open("palette/palette_catalog.json").bufferedReader().use { reader ->
                val root = JSONObject(reader.readText())
                PaletteCatalog(
                    franchises = root.optJSONArray("franchises").orEmpty().mapNotNull { item ->
                        val json = item as? JSONObject ?: return@mapNotNull null
                        val id = json.optString("id").trim()
                        if (id.isBlank()) return@mapNotNull null
                        PaletteFranchise(
                            id = id,
                            label = json.optString("label").trim(),
                            labelZh = json.optString("labelZh")
                                .ifBlank { json.optString("label").trim() }
                                .trim(),
                            labelJa = json.optString("labelJa")
                                .ifBlank { json.optString("label").trim() }
                                .trim(),
                            sortOrder = json.optInt("sortOrder"),
                        )
                    },
                    groups = root.optJSONArray("groups").orEmpty().mapNotNull { item ->
                        val json = item as? JSONObject ?: return@mapNotNull null
                        val id = json.optString("id").trim()
                        if (id.isBlank()) return@mapNotNull null
                        PaletteGroup(
                            id = id,
                            franchiseId = json.optString("franchiseId").trim(),
                            seriesLabelZh = json.optString("seriesLabelZh")
                                .ifBlank { json.optString("seriesLabel").trim() }
                                .trim(),
                            seriesLabelJa = json.optString("seriesLabelJa")
                                .ifBlank { json.optString("seriesLabel").trim() }
                                .trim(),
                            nameZh = json.optString("nameZh")
                                .ifBlank { json.optString("name").trim() }
                                .trim(),
                            nameJa = json.optString("nameJa")
                                .ifBlank { json.optString("name").trim() }
                                .trim(),
                            sourceName = json.optString("sourceName").trim(),
                            hex = normalizeHex(json.optString("hex")) ?: "#808080",
                            image = json.optString("image").trim(),
                            memberIds = json.optJSONArray("memberIds").orEmpty().mapNotNull { value ->
                                value as? String
                            },
                            sourceUrl = json.optString("sourceUrl").trim(),
                            imageSourceUrl = json.optString("imageSourceUrl").trim(),
                            groupType = json.optString("groupType").trim(),
                            sortOrder = json.optInt("sortOrder"),
                            imageKind = json.optString("imageKind").trim().ifBlank { "avatar" },
                        )
                    },
                    characters = root.optJSONArray("characters").orEmpty().mapNotNull { item ->
                        val json = item as? JSONObject ?: return@mapNotNull null
                        val id = json.optString("id").trim()
                        if (id.isBlank()) return@mapNotNull null
                        PaletteCharacter(
                            id = id,
                            franchiseId = json.optString("franchiseId").trim(),
                            groupId = json.optString("groupId").trim(),
                            nameZh = json.optString("nameZh")
                                .ifBlank { json.optString("name").trim() }
                                .trim(),
                            nameJa = json.optString("nameJa")
                                .ifBlank { json.optString("name").trim() }
                                .trim(),
                            hex = normalizeHex(json.optString("hex")) ?: "#808080",
                            image = json.optString("image").trim(),
                            sourceUrl = json.optString("sourceUrl").trim(),
                            imageSourceUrl = json.optString("imageSourceUrl").trim(),
                            sortOrder = json.optInt("sortOrder"),
                        )
                    },
                )
            }
        } catch (_: Exception) {
            PaletteCatalog.Empty
        }
    }

    fun buildHierarchy(catalog: PaletteCatalog): PaletteHierarchyUiState {
        val visibleGroups = catalog.groups
            .filter { group -> group.groupType !in setOf("attribute", "unit") }
            .sortedWith(
                compareBy<PaletteGroup> { it.franchiseId }
                    .thenBy { it.sortOrder }
                    .thenBy { it.nameZh },
            )

        val charactersByGroupId = catalog.characters
            .groupBy { it.groupId }
            .mapValues { (_, items) -> items.sortedBy { it.sortOrder } }

        val groupsByFranchise = visibleGroups.groupBy { it.franchiseId }
            .mapValues { (_, items) -> items.sortedBy { it.sortOrder } }

        val sectionsByFranchise = groupsByFranchise.mapValues { (_, groups) ->
            groups.groupBy { "${it.seriesLabelZh}\u0000${it.seriesLabelJa}" }
                .map { (labelKey, items) ->
                    val labels = labelKey.split('\u0000', limit = 2)
                    PaletteGroupSection(
                        labelZh = labels.getOrNull(0).orEmpty().ifBlank { "未分组" },
                        labelJa = labels.getOrNull(1).orEmpty().ifBlank { "未分類" },
                        groups = items.sortedBy { it.sortOrder },
                    )
                }
                .sortedBy { section -> section.groups.minOfOrNull { it.sortOrder } ?: Int.MAX_VALUE }
        }

        return PaletteHierarchyUiState(
            franchises = catalog.franchises.sortedBy { it.sortOrder },
            groupsByFranchise = groupsByFranchise,
            sectionsByFranchise = sectionsByFranchise,
            charactersByGroupId = charactersByGroupId,
        )
    }

    fun resolveImagePath(raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isBlank()) return null
        if (
            trimmed.startsWith("http://") ||
            trimmed.startsWith("https://") ||
            trimmed.startsWith("file://")
        ) {
            return trimmed
        }
        val cleaned = trimmed.removePrefix("/").removePrefix("assets/")
        return "file:///android_asset/$cleaned"
    }

    private fun normalizeHex(input: String?): String? {
        val raw = input?.trim().orEmpty()
        if (raw.isBlank()) return null
        val value = raw.removePrefix("#")
        if (!value.matches(Regex("[0-9a-fA-F]{6}"))) return null
        return "#${value.uppercase()}"
    }
}

private fun org.json.JSONArray?.orEmpty(): List<Any?> {
    if (this == null) return emptyList()
    return List(length()) { index -> opt(index) }
}
