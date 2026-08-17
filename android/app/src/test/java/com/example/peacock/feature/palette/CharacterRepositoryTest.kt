package com.example.peacock.feature.palette

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CharacterRepositoryTest {
    @Test
    fun `buildHierarchy hides extra imas groups from second level`() {
        val catalog = PaletteCatalog(
            franchises = listOf(
                PaletteFranchise(id = "imas", label = "THE IDOLM@STER", sortOrder = 1),
            ),
            groups = listOf(
                PaletteGroup(
                    id = "imas_cinderella",
                    franchiseId = "imas",
                    seriesLabelZh = "企划",
                    seriesLabelJa = "企画",
                    nameZh = "灰姑娘女孩",
                    nameJa = "シンデレラガールズ",
                    sourceName = "シンデレラガールズ",
                    hex = "#2681C8",
                    image = "palette/groups/imas_cinderella.png",
                    memberIds = listOf("char_1"),
                    sourceUrl = "",
                    imageSourceUrl = "",
                    groupType = "brand",
                    sortOrder = 1,
                ),
                PaletteGroup(
                    id = "imas_extra_cute",
                    franchiseId = "imas",
                    seriesLabelZh = "灰姑娘女孩",
                    seriesLabelJa = "シンデレラガールズ",
                    nameZh = "Cute",
                    nameJa = "キュート",
                    sourceName = "キュート",
                    hex = "#EF2782",
                    image = "palette/groups/imas_extra_cute.png",
                    memberIds = emptyList(),
                    sourceUrl = "",
                    imageSourceUrl = "",
                    groupType = "attribute",
                    sortOrder = 1000,
                ),
            ),
            characters = listOf(
                PaletteCharacter(
                    id = "char_1",
                    franchiseId = "imas",
                    groupId = "imas_cinderella",
                    nameZh = "涩谷凛",
                    nameJa = "渋谷凛",
                    hex = "#7A508F",
                    image = "palette/characters/char_1.png",
                    sourceUrl = "",
                    imageSourceUrl = "",
                    sortOrder = 1,
                ),
            ),
        )

        val hierarchy = CharacterRepository.buildHierarchy(catalog)

        assertEquals(1, hierarchy.franchises.size)
        assertEquals(1, hierarchy.groupsByFranchise["imas"].orEmpty().size)
        assertEquals("灰姑娘女孩", hierarchy.groupsByFranchise["imas"].orEmpty().first().nameZh)
        assertEquals("企划", hierarchy.sectionsByFranchise["imas"].orEmpty().firstOrNull()?.labelZh)
        assertEquals("企画", hierarchy.sectionsByFranchise["imas"].orEmpty().firstOrNull()?.labelJa)
        assertEquals(1, hierarchy.charactersByGroupId["imas_cinderella"].orEmpty().size)
    }

    @Test
    fun `generated palette catalog contains updated imas section labels`() {
        val catalogText = File("src/main/assets/palette/palette_catalog.json").readText(Charsets.UTF_8)

        assertTrue(catalogText.contains("\"label\": \"BangDream\""))
        assertTrue(catalogText.contains("\"label\": \"LoveLive!\""))
        assertTrue(catalogText.contains("\"label\": \"THE IDOLM@STER\""))
        assertTrue(catalogText.contains("\"seriesLabelZh\": \"企划\""))
        assertTrue(catalogText.contains("\"seriesLabelJa\": \"企画\""))
        assertFalse(catalogText.contains("\"seriesLabelZh\": \"品牌\""))
        assertFalse(catalogText.contains("\"seriesLabelJa\": \"ブランド\""))
        assertEquals(8, Regex("\"imageKind\": \"logo\"").findAll(catalogText).count())
        assertTrue(catalogText.contains("\"nameZh\": \"vα-liv\""))
        assertTrue(catalogText.contains("\"id\": \"imas_char_210003\""))
        assertTrue(catalogText.contains("\"id\": \"imas_char_210004\""))
        assertTrue(catalogText.contains("\"id\": \"imas_char_210005\""))
    }
}
