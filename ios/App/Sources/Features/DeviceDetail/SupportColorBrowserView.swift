import MauryaDevice
import MauryaResources
import SwiftUI
import UIKit

struct SupportColorBrowserView: View {
    @Environment(\.locale) private var locale
    let service: any ResourceLibraryService
    let controlService: any DeviceControlService
    @State private var selectedFranchiseID = ""
    @State private var selectedGroupID = ""
    @State private var groupSearch = ""
    @State private var memberSearch = ""

    var body: some View {
        Group {
            if let snapshot = service.snapshot {
                paletteList(snapshot)
            } else if let error = service.errorMessage {
                ContentUnavailableView(
                    "state.error.title",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ProgressView("state.loading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(DesignTokens.Color.background)
        .task {
            await service.load()
            selectInitialFranchiseIfNeeded()
        }
        .onChange(of: service.snapshot?.catalog) {
            selectInitialFranchiseIfNeeded()
        }
    }

    private func paletteList(_ snapshot: ResourceLibrarySnapshot) -> some View {
        let hierarchy = PaletteHierarchy(catalog: snapshot.catalog)
        let entries = Dictionary(uniqueKeysWithValues: snapshot.entries.map { ($0.id, $0) })
        let groups = filteredGroups(hierarchy.groupsByFranchise[selectedFranchiseID].orEmpty)
        let characters = filteredCharacters(hierarchy.charactersByGroup[selectedGroupID].orEmpty)

        return List {
            Section("palette.franchise") {
                PaletteFranchiseSelectorView(
                    franchises: hierarchy.franchises,
                    locale: paletteLocale,
                    selection: $selectedFranchiseID,
                    showCustom: true
                )
            }
            .listRowBackground(DesignTokens.Color.background)

            if selectedFranchiseID == "custom" {
                customRows(snapshot.customEntries)
            } else {
                Section("resources.groups") {
                    TextField("resources.search", text: $groupSearch)
                        .textFieldStyle(.roundedBorder)
                    if groups.isEmpty {
                        ContentUnavailableView.search
                    } else {
                        ForEach(groups) { group in
                            PaletteGroupCardView(
                                group: group,
                                entry: entries[group.id],
                                locale: paletteLocale,
                                isSelected: selectedGroupID == group.id,
                                open: { open(group) },
                                selectColor: { applyColor(entries[group.id]) }
                            )
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowBackground(DesignTokens.Color.background)
                        }
                    }
                }

                if selectedGroupID.isEmpty == false {
                    Section("resources.characters") {
                        TextField("resources.search", text: $memberSearch)
                            .textFieldStyle(.roundedBorder)
                        if characters.isEmpty {
                            ContentUnavailableView.search
                        } else {
                            ForEach(characters) { character in
                                PaletteCharacterRowView(
                                    character: character,
                                    entry: entries[character.id],
                                    locale: paletteLocale,
                                    select: { applyColor(entries[character.id]) }
                                )
                                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                                .listRowBackground(DesignTokens.Color.background)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(DesignTokens.Color.background)
        .accessibilityIdentifier("support-color-browser")
    }

    @ViewBuilder
    private func customRows(_ entries: [CustomPalettePresentation]) -> some View {
        Section("resources.custom") {
            if entries.isEmpty {
                ContentUnavailableView(
                    "resources.custom",
                    systemImage: "paintpalette",
                    description: Text("state.empty.message")
                )
            } else {
                ForEach(entries) { item in
                    Button {
                        if let selection = SupportColorSelection(custom: item.entry) {
                            applyColor(selection)
                        }
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.standard) {
                            if let image = UIImage(data: item.avatarWebP) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(Circle())
                            }
                            VStack(alignment: .leading) {
                                Text(item.entry.names.zh.isEmpty ? item.entry.names.ja : item.entry.names.zh)
                                    .font(.headline)
                                Text(item.entry.color.rawValue)
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(DesignTokens.Color.onSurfaceVariant)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("palette.select.hint")
                }
            }
        }
        .listRowBackground(DesignTokens.Color.surface)
    }

    private var paletteLocale: PaletteLocale {
        locale.language.languageCode?.identifier == "ja" ? .japanese : .simplifiedChinese
    }

    private func selectInitialFranchiseIfNeeded() {
        guard selectedFranchiseID.isEmpty, let first = service.snapshot?.catalog.franchises.first else { return }
        selectedFranchiseID = first.id
    }

    private func open(_ group: PaletteGroup) {
        selectedGroupID = group.id
        memberSearch = ""
    }

    private func applyColor(_ entry: ResourceInventoryEntry?) {
        guard let entry, let selection = SupportColorSelection(entry: entry) else { return }
        applyColor(selection)
    }

    private func applyColor(_ selection: SupportColorSelection) {
        Task {
            await controlService.applyColorToAllGroups(
                hue: selection.hue,
                saturation: selection.saturation,
                value: selection.value
            )
        }
    }

    private func filteredGroups(_ groups: [PaletteGroup]) -> [PaletteGroup] {
        guard groupSearch.isEmpty == false else { return groups }
        return groups.filter {
            $0.nameZh.localizedStandardContains(groupSearch)
                || $0.nameJa.localizedStandardContains(groupSearch)
                || $0.seriesLabelZh.localizedStandardContains(groupSearch)
                || $0.seriesLabelJa.localizedStandardContains(groupSearch)
        }
    }

    private func filteredCharacters(_ characters: [PaletteCharacter]) -> [PaletteCharacter] {
        guard memberSearch.isEmpty == false else { return characters }
        return characters.filter {
            $0.nameZh.localizedStandardContains(memberSearch)
                || $0.nameJa.localizedStandardContains(memberSearch)
        }
    }

}

private extension Optional where Wrapped == [PaletteGroup] {
    var orEmpty: [PaletteGroup] { self ?? [] }
}

private extension Optional where Wrapped == [PaletteCharacter] {
    var orEmpty: [PaletteCharacter] { self ?? [] }
}
