import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    @Binding var showsFlaggedOnly: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search stuff…", text: $text)
                    .submitLabel(.search)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                showsFlaggedOnly.toggle()
            } label: {
                Image(systemName: showsFlaggedOnly ? "flag.fill" : "flag")
                    .font(.body.weight(.semibold))
                    .frame(width: 38, height: 38)
            }
            .foregroundStyle(showsFlaggedOnly ? .white : .orange)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(showsFlaggedOnly ? Color.orange : Color(.secondarySystemBackground))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.orange.opacity(showsFlaggedOnly ? 0 : 0.32), lineWidth: 0.75)
            }
            .accessibilityLabel(showsFlaggedOnly ? "Showing flagged items" : "Show flagged items")
            .accessibilityAddTraits(showsFlaggedOnly ? .isSelected : [])
        }
        .animation(.easeInOut(duration: 0.2), value: text.isEmpty)
        .animation(.easeInOut(duration: 0.16), value: showsFlaggedOnly)
    }
}
