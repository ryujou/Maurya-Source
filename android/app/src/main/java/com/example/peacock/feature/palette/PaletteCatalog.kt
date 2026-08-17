package com.example.peacock.feature.palette

data class PaletteCatalog(
    val franchises: List<PaletteFranchise>,
    val groups: List<PaletteGroup>,
    val characters: List<PaletteCharacter>,
) {
    companion object {
        val Empty = PaletteCatalog(
            franchises = emptyList(),
            groups = emptyList(),
            characters = emptyList(),
        )
    }
}

data class PaletteFranchise(
    val id: String,
    val label: String,
    val sortOrder: Int,
    val labelZh: String = label,
    val labelJa: String = label,
) {
    fun displayLabel(useJapanese: Boolean): String = if (useJapanese) labelJa else labelZh
}

data class PaletteGroup(
    val id: String,
    val franchiseId: String,
    val seriesLabelZh: String,
    val seriesLabelJa: String,
    val nameZh: String,
    val nameJa: String,
    val sourceName: String,
    val hex: String,
    val image: String,
    val memberIds: List<String>,
    val sourceUrl: String,
    val imageSourceUrl: String,
    val groupType: String,
    val sortOrder: Int,
    val imageKind: String = "avatar",
) {
    fun displayName(useJapanese: Boolean): String = if (useJapanese) nameJa else nameZh

    fun displaySeriesLabel(useJapanese: Boolean): String = if (useJapanese) seriesLabelJa else seriesLabelZh
}

data class PaletteCharacter(
    val id: String,
    val franchiseId: String,
    val groupId: String,
    val nameZh: String,
    val nameJa: String,
    val hex: String,
    val image: String,
    val sourceUrl: String,
    val imageSourceUrl: String,
    val sortOrder: Int,
) {
    fun displayName(useJapanese: Boolean): String = if (useJapanese) nameJa else nameZh
}

data class PaletteGroupSection(
    val labelZh: String,
    val labelJa: String,
    val groups: List<PaletteGroup>,
) {
    fun displayLabel(useJapanese: Boolean): String = if (useJapanese) labelJa else labelZh
}

data class PaletteHierarchyUiState(
    val franchises: List<PaletteFranchise>,
    val groupsByFranchise: Map<String, List<PaletteGroup>>,
    val sectionsByFranchise: Map<String, List<PaletteGroupSection>>,
    val charactersByGroupId: Map<String, List<PaletteCharacter>>,
) {
    companion object {
        val Empty = PaletteHierarchyUiState(
            franchises = emptyList(),
            groupsByFranchise = emptyMap(),
            sectionsByFranchise = emptyMap(),
            charactersByGroupId = emptyMap(),
        )
    }
}
