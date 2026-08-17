package com.example.peacock.ui.screen.palette

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.example.peacock.R
import com.example.peacock.feature.palette.CharacterRepository
import com.example.peacock.feature.palette.CustomPaletteViewModel
import com.example.peacock.feature.palette.PaletteCharacter
import com.example.peacock.feature.palette.PaletteGroup
import com.example.peacock.feature.palette.PaletteGroupSection
import com.example.peacock.feature.palette.PaletteHierarchyUiState
import com.example.peacock.ui.component.ColorPreview
import com.example.peacock.ui.component.ModeButton
import com.example.peacock.ui.i18n.AppLanguageManager
import com.example.peacock.ui.i18n.DisplayLanguage

@Composable
fun CharacterPaletteScreen(
    hierarchy: PaletteHierarchyUiState,
    customPaletteViewModel: CustomPaletteViewModel,
    onPickGroupColor: (String) -> Unit,
    onPickCharacterColor: (String) -> Unit,
    onBackToConsole: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val useJapanese = AppLanguageManager.currentDisplayLanguage(context) == DisplayLanguage.JA_JP

    var selectedFranchiseId by remember(hierarchy.franchises) {
        mutableStateOf(hierarchy.franchises.firstOrNull()?.id.orEmpty())
    }
    var groupSearch by remember { mutableStateOf("") }
    var memberSearch by remember { mutableStateOf("") }
    val copy = remember(selectedFranchiseId, useJapanese) {
        resolvePaletteCopy(context, selectedFranchiseId)
    }

    val allGroups = remember(selectedFranchiseId, hierarchy.groupsByFranchise) {
        hierarchy.groupsByFranchise[selectedFranchiseId].orEmpty()
    }

    var selectedGroupId by remember(selectedFranchiseId) {
        mutableStateOf("")
    }

    val filteredSections = remember(selectedFranchiseId, groupSearch, hierarchy.sectionsByFranchise, useJapanese) {
        hierarchy.sectionsByFranchise[selectedFranchiseId].orEmpty().mapNotNull { section ->
            val groups = section.groups.filter { group ->
                groupSearch.isBlank() ||
                    group.displayName(useJapanese).contains(groupSearch, ignoreCase = true) ||
                    group.nameZh.contains(groupSearch, ignoreCase = true) ||
                    group.nameJa.contains(groupSearch, ignoreCase = true) ||
                    group.displaySeriesLabel(useJapanese).contains(groupSearch, ignoreCase = true) ||
                    group.seriesLabelZh.contains(groupSearch, ignoreCase = true) ||
                    group.seriesLabelJa.contains(groupSearch, ignoreCase = true)
            }
            if (groups.isEmpty()) null else PaletteGroupSection(section.labelZh, section.labelJa, groups)
        }
    }

    val visibleGroupIds = remember(filteredSections) {
        filteredSections.flatMap { section -> section.groups.map { it.id } }.toSet()
    }

    LaunchedEffect(visibleGroupIds) {
        if (selectedGroupId !in visibleGroupIds) {
            selectedGroupId = ""
            memberSearch = ""
        }
    }

    val selectedGroup = remember(selectedGroupId, allGroups) {
        allGroups.firstOrNull { it.id == selectedGroupId }
    }

    val filteredMembers = remember(selectedGroupId, memberSearch, hierarchy.charactersByGroupId, useJapanese) {
        hierarchy.charactersByGroupId[selectedGroupId].orEmpty().filter { member ->
            memberSearch.isBlank() ||
                member.displayName(useJapanese).contains(memberSearch, ignoreCase = true) ||
                member.nameZh.contains(memberSearch, ignoreCase = true) ||
                member.nameJa.contains(memberSearch, ignoreCase = true)
        }
    }

    LazyColumn(
        modifier = modifier.fillMaxSize().testTag("palette-page"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.palette_title), style = MaterialTheme.typography.titleMedium)
                onBackToConsole?.let { back ->
                    Button(onClick = back, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.back_to_console))
                    }
                }
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    hierarchy.franchises.forEach { franchise ->
                        ModeButton(
                            text = franchise.displayLabel(useJapanese),
                            selected = selectedFranchiseId == franchise.id,
                            onClick = {
                                selectedFranchiseId = franchise.id
                                groupSearch = ""
                                memberSearch = ""
                                selectedGroupId = ""
                            },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    ModeButton(
                        text = if (useJapanese) "マイ応援カラー" else "我的应援色",
                        selected = selectedFranchiseId == "custom",
                        onClick = {
                            selectedFranchiseId = "custom"
                            groupSearch = ""
                            memberSearch = ""
                            selectedGroupId = ""
                        },
                        modifier = Modifier.fillMaxWidth().testTag("palette-franchise-custom"),
                    )
                }
                if (selectedFranchiseId != "custom") {
                    OutlinedTextField(
                        value = groupSearch,
                        onValueChange = { groupSearch = it },
                        label = { Text(copy.groupSearchLabel) },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                    )
                }
            }
        }

        if (selectedFranchiseId == "custom") {
            item {
                CustomPalettePanel(
                    viewModel = customPaletteViewModel,
                    useJapanese = useJapanese,
                    onApplyColor = onPickCharacterColor,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }

        if (selectedFranchiseId != "custom" && filteredSections.isEmpty()) {
            item {
                Text(
                    text = copy.noGroupMessage,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }

        val showSectionHeaders = selectedFranchiseId == "lovelive" && filteredSections.size > 1
        items(
            items = if (selectedFranchiseId == "custom") emptyList() else filteredSections,
            key = { section -> "${selectedFranchiseId}_${section.labelZh}_${section.labelJa}" },
        ) { section ->
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (showSectionHeaders) {
                    Text(
                        text = section.displayLabel(useJapanese),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
                section.groups.forEach { group ->
                    GroupRow(
                        group = group,
                        useJapanese = useJapanese,
                        selected = group.id == selectedGroupId,
                        onOpen = {
                            selectedGroupId = group.id
                            memberSearch = ""
                        },
                        onApplyColor = { onPickGroupColor(group.hex) },
                    )
                }
            }
        }

        if (selectedGroup != null) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        text = copy.memberListTitle(selectedGroup.displayName(useJapanese)),
                        style = MaterialTheme.typography.titleSmall,
                    )
                    OutlinedTextField(
                        value = memberSearch,
                        onValueChange = { memberSearch = it },
                        label = { Text(copy.memberSearchLabel) },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                    )
                }
            }
        }

        if (selectedGroup != null && filteredMembers.isEmpty()) {
            item {
                Text(
                    text = copy.noMemberMessage,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }

        if (selectedGroup != null && filteredMembers.isNotEmpty()) {
            items(
                items = filteredMembers,
                key = { member -> member.id },
            ) { member ->
                CharacterRow(
                    item = member,
                    useJapanese = useJapanese,
                    onClick = { onPickCharacterColor(member.hex) },
                )
            }
        }
    }
}

@Composable
private fun GroupRow(
    group: PaletteGroup,
    useJapanese: Boolean,
    selected: Boolean,
    onOpen: () -> Unit,
    onApplyColor: () -> Unit,
) {
    if (group.imageKind == "logo") {
        LogoGroupCard(group, useJapanese, selected, onOpen, onApplyColor)
        return
    }

    val imagePath = remember(group.image) { CharacterRepository.resolveImagePath(group.image) }
    val previewColor = remember(group.hex) { colorFromHex(group.hex) }

    ElevatedCard(
        modifier = Modifier.fillMaxWidth(),
    ) {
        androidx.compose.foundation.layout.Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            AvatarImage(
                imagePath = imagePath,
                contentDescription = group.displayName(useJapanese),
                fallbackText = group.displayName(useJapanese).take(2),
                modifier = Modifier.clickable(onClick = onApplyColor),
            )
            Column(
                modifier = Modifier
                    .weight(1f)
                    .clickable(onClick = onOpen)
                    .testTag("palette-group-${group.id}")
                    .padding(vertical = 8.dp),
            ) {
                Text(
                    text = group.displayName(useJapanese),
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            ColorPreview(previewColor, Modifier.clickable(onClick = onApplyColor))
        }
    }
}

@Composable
private fun LogoGroupCard(
    group: PaletteGroup,
    useJapanese: Boolean,
    selected: Boolean,
    onOpen: () -> Unit,
    onApplyColor: () -> Unit,
) {
    val imagePath = remember(group.image) { CharacterRepository.resolveImagePath(group.image) }
    val previewColor = remember(group.hex) { colorFromHex(group.hex) }
    val selectedBorder = if (selected) MaterialTheme.colorScheme.primary else Color.Transparent

    ElevatedCard(
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, selectedBorder, MaterialTheme.shapes.medium)
            .testTag("project-logo-${group.id}"),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(112.dp)
                .background(Color(0xFFF6F7FB))
                .clickable(onClick = onApplyColor)
                .padding(horizontal = 18.dp, vertical = 10.dp),
            contentAlignment = Alignment.Center,
        ) {
            if (imagePath != null) {
                AsyncImage(
                    model = imagePath,
                    contentDescription = "${group.displayName(useJapanese)} logo",
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Fit,
                )
            } else {
                Text(
                    text = group.displayName(useJapanese),
                    color = Color(0xFF151824),
                    fontWeight = FontWeight.Bold,
                )
            }
        }
        androidx.compose.foundation.layout.Row(
            modifier = Modifier
                .clickable(onClick = onOpen)
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = group.displayName(useJapanese),
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = "${group.displaySeriesLabel(useJapanese)} · ${group.hex}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            ColorPreview(previewColor)
        }
    }
}

@Composable
private fun CharacterRow(
    item: PaletteCharacter,
    useJapanese: Boolean,
    onClick: () -> Unit,
) {
    val imagePath = remember(item.image) { CharacterRepository.resolveImagePath(item.image) }
    val previewColor = remember(item.hex) { colorFromHex(item.hex) }

    ElevatedCard(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .testTag("palette-character-${item.id}"),
    ) {
        androidx.compose.foundation.layout.Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            val (avatarZoom, avatarTransformOrigin) = when (item.franchiseId) {
                "lovelive" -> 1.08f to TransformOrigin(0.5f, 0.28f)
                "imas" -> 1.05f to TransformOrigin(0.5f, 0.32f)
                else -> 1f to TransformOrigin.Center
            }
            AvatarImage(
                imagePath = imagePath,
                contentDescription = item.displayName(useJapanese),
                fallbackText = item.displayName(useJapanese).take(1),
                zoom = avatarZoom,
                transformOrigin = avatarTransformOrigin,
            )
            Text(
                text = item.displayName(useJapanese),
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.weight(1f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            ColorPreview(previewColor)
        }
    }
}

@Composable
private fun AvatarImage(
    imagePath: String?,
    contentDescription: String,
    fallbackText: String,
    zoom: Float = 1f,
    transformOrigin: TransformOrigin = TransformOrigin.Center,
    modifier: Modifier = Modifier,
) {
    if (imagePath != null) {
        AsyncImage(
            model = imagePath,
            contentDescription = contentDescription,
            modifier = modifier
                .size(52.dp)
                .clip(CircleShape)
                .graphicsLayer {
                    scaleX = zoom
                    scaleY = zoom
                    this.transformOrigin = transformOrigin
                },
            contentScale = ContentScale.Crop,
        )
    } else {
        Box(
            modifier = modifier
                .size(52.dp)
                .clip(CircleShape)
                .background(Color.Gray.copy(alpha = 0.2f)),
            contentAlignment = Alignment.Center,
        ) {
            Text(fallbackText)
        }
    }
}

private fun colorFromHex(hex: String): Color {
    return runCatching { Color(android.graphics.Color.parseColor(hex)) }
        .getOrElse { Color.Gray }
}
