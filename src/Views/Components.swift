import SwiftUI

/// Capsule filter bar — pill selector styled after the web accent.
struct PillPicker: View {
    let options: [String]
    @Binding var selection: Int
    var accent: Color = .cyan

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options.indices, id: \.self) { i in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = i }
                } label: {
                    Text(options[i])
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selection == i ? accent : Color.white.opacity(0.14))
                        .foregroundStyle(selection == i ? Color.white : Color.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}

extension View {
    /// Frosted card for rows floating over the themed gradient.
    func themeCard(padding: CGFloat = 12) -> some View {
        self
            .padding(padding)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
