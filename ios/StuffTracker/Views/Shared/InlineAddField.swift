import SwiftUI

struct InlineAddField: View {
    let placeholder: String
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { if !text.isEmpty { onCommit() } }
                .padding(8)
                .background(CubbyTheme.paper.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(CubbyTheme.floorBorder.opacity(0.75), lineWidth: 0.75)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: onCommit) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .frame(width: 34, height: 34)
                    .cubbyWoodButtonSurface(isEnabled: !text.isEmpty)
            }
            .buttonStyle(.plain)
            .disabled(text.isEmpty)

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .frame(width: 34, height: 34)
                    .cubbyWoodButtonSurface()
            }
            .buttonStyle(.plain)
        }
        .onAppear { focused = true }
    }
}

struct AddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.body.bold())
                .frame(width: 34, height: 34)
                .cubbyWoodButtonSurface()
        }
        .buttonStyle(.plain)
    }
}
