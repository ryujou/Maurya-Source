import MauryaResources
import PhotosUI
import SwiftUI
import UIKit

struct CustomPaletteEditorView: View {
    let existing: CustomPaletteEntry?
    let existingAvatar: Data?
    let onSave: (String, String, String, Data?, AvatarCropTransform) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var nameZh: String
    @State private var nameJa: String
    @State private var hex: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var imageError = false
    @State private var saveError = false
    @State private var saving = false
    @State private var cropTransform = AvatarCropTransform()
    @State private var candidateColors: [String] = []
    @GestureState private var liveMagnification = 1.0
    @GestureState private var liveDrag = CGSize.zero

    init(
        existing: CustomPaletteEntry?,
        existingAvatar: Data?,
        onSave: @escaping (String, String, String, Data?, AvatarCropTransform) async -> Bool
    ) {
        self.existing = existing
        self.existingAvatar = existingAvatar
        self.onSave = onSave
        _nameZh = State(initialValue: existing?.names.zh ?? "")
        _nameJa = State(initialValue: existing?.names.ja ?? "")
        _hex = State(initialValue: existing?.color.rawValue ?? "#FF8800")
        _imageData = State(initialValue: existingAvatar)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("resources.custom.names") {
                    TextField("resources.custom.name.zh", text: $nameZh)
                    TextField("resources.custom.name.ja", text: $nameJa)
                }
                Section("resources.custom.color") {
                    HStack {
                        Circle().fill(previewColor).frame(width: 32, height: 32)
                            .accessibilityHidden(true)
                        TextField("#RRGGBB", text: $hex)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                }
                Section("resources.custom.avatar") {
                    if let imageData, let image = UIImage(data: imageData) {
                        GeometryReader { proxy in
                            let side = min(proxy.size.width, 300)
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: side, height: side)
                                .scaleEffect(cropTransform.zoom * liveMagnification)
                                .rotationEffect(.degrees(Double(cropTransform.quarterTurns * 90)))
                                .offset(
                                    x: cropTransform.offsetX * side + liveDrag.width,
                                    y: cropTransform.offsetY * side + liveDrag.height
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                                .overlay { Circle().stroke(.white, lineWidth: 3).padding(12) }
                                .background(Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
                                .gesture(
                                    MagnifyGesture()
                                        .updating($liveMagnification) { value, state, _ in state = value.magnification }
                                        .onEnded { value in
                                            cropTransform.zoom = min(6, max(1, cropTransform.zoom * value.magnification))
                                        }
                                )
                                .simultaneousGesture(
                                    DragGesture()
                                        .updating($liveDrag) { value, state, _ in state = value.translation }
                                        .onEnded { value in
                                            cropTransform.offsetX = min(2, max(-2, cropTransform.offsetX + value.translation.width / side))
                                            cropTransform.offsetY = min(2, max(-2, cropTransform.offsetY + value.translation.height / side))
                                        }
                                )
                        }
                        .frame(height: 300)
                        ViewThatFits(in: .horizontal) {
                            HStack { photoActionButtons(imageData) }
                            VStack(alignment: .leading) { photoActionButtons(imageData) }
                        }
                        if candidateColors.isEmpty == false {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))]) {
                                ForEach(candidateColors, id: \.self) { candidate in
                                    Button {
                                        hex = candidate
                                    } label: {
                                        Circle().fill(color(candidate)).frame(width: 38, height: 38)
                                            .overlay { Circle().stroke(.white, lineWidth: 2) }
                                    }
                                    .accessibilityLabel(candidate)
                                }
                            }
                        }
                    }
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("resources.custom.photo.choose", systemImage: "photo.on.rectangle")
                    }
                    if imageData != nil { Label("resources.custom.photo.chosen", systemImage: "checkmark.circle") }
                    Text("resources.custom.photo.contract").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(existing == nil ? "resources.custom.add" : "resources.custom.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") {
                        saving = true
                        Task {
                            let saved = await onSave(nameZh, nameJa, hex.uppercased(), imageData, cropTransform)
                            saving = false
                            if saved { dismiss() } else { saveError = true }
                        }
                    }
                    .disabled(isInvalid || saving)
                }
            }
            .onChange(of: selectedPhoto) {
                guard let selectedPhoto else { return }
                Task {
                    do {
                        imageData = try await selectedPhoto.loadTransferable(type: Data.self)
                        cropTransform = .init()
                        candidateColors =
                            imageData.flatMap {
                                try? AvatarImageProcessor.candidateColors($0)
                            } ?? []
                        if existing == nil, let first = candidateColors.first { hex = first }
                        imageError = imageData == nil
                    } catch {
                        imageError = true
                    }
                }
            }
            .alert("resources.custom.photo.error.title", isPresented: $imageError) {
                Button("action.ok", role: .cancel) {}
            } message: {
                Text("resources.custom.photo.error.message")
            }
            .alert("resources.custom.save.error.title", isPresented: $saveError) {
            } message: {
                Text("resources.custom.save.error.message")
            }
            .interactiveDismissDisabled(saving)
        }
    }

    @ViewBuilder
    private func photoActionButtons(_ imageData: Data) -> some View {
        Button("resources.custom.photo.rotate", systemImage: "rotate.right") {
            cropTransform.quarterTurns = (cropTransform.quarterTurns + 1) % 4
        }
        Button("resources.custom.photo.reset", systemImage: "arrow.counterclockwise") {
            cropTransform = .init()
        }
        Button("resources.custom.color.extract", systemImage: "eyedropper") {
            candidateColors =
                (try? AvatarImageProcessor.candidateColors(
                    imageData,
                    transform: cropTransform
                )) ?? []
            if let first = candidateColors.first { hex = first }
        }
    }

    private var isInvalid: Bool {
        (nameZh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && nameJa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || hex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) == nil || (existing == nil && imageData == nil)
    }

    private var previewColor: Color {
        guard let value = UInt64(hex.dropFirst(), radix: 16), hex.count == 7 else { return .clear }
        return Color(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    private func color(_ hex: String) -> Color {
        guard let value = UInt64(hex.dropFirst(), radix: 16), hex.count == 7 else { return .clear }
        return Color(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}
