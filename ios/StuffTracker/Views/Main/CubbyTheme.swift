import SwiftUI

enum CubbySurfaceKind {
    case home
    case floor
    case room
    case container
}

enum CubbyTheme {
    static let wallTop = Color(red: 0.98, green: 0.91, blue: 0.82)
    static let wallMiddle = Color(red: 0.96, green: 0.84, blue: 0.70)
    static let wallBottom = Color(red: 0.88, green: 0.69, blue: 0.48)
    static let warmInk = Color(red: 0.18, green: 0.12, blue: 0.08)
    static let green = Color(red: 0.18, green: 0.34, blue: 0.29)
    static let greenSoft = Color(red: 0.82, green: 0.90, blue: 0.82)
    static let amber = Color(red: 0.78, green: 0.43, blue: 0.20)
    static let paper = Color(red: 1.00, green: 0.97, blue: 0.91)
    static let paperDeep = Color(red: 0.96, green: 0.88, blue: 0.76)
    static let shelfShadow = Color(red: 0.31, green: 0.18, blue: 0.09)
    static let homeBorder = Color(red: 0.54, green: 0.31, blue: 0.15).opacity(0.34)
    static let floorBorder = Color(red: 0.60, green: 0.38, blue: 0.19).opacity(0.24)
    static let roomBorder = Color(red: 0.62, green: 0.43, blue: 0.24).opacity(0.18)
    static let containerBorder = Color(red: 0.55, green: 0.38, blue: 0.20).opacity(0.16)

    static func surfaceGradient(for kind: CubbySurfaceKind) -> LinearGradient {
        switch kind {
        case .home:
            return LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.77, blue: 0.51),
                    Color(red: 0.88, green: 0.60, blue: 0.34),
                    Color(red: 0.74, green: 0.45, blue: 0.23),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .floor:
            return LinearGradient(
                colors: [
                    Color(red: 0.99, green: 0.89, blue: 0.73),
                    Color(red: 0.94, green: 0.77, blue: 0.54),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .room:
            return LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.96, blue: 0.88),
                    Color(red: 0.98, green: 0.89, blue: 0.76),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .container:
            return LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.98, blue: 0.93),
                    Color(red: 0.96, green: 0.89, blue: 0.78),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    static func shelfLip(for kind: CubbySurfaceKind) -> LinearGradient {
        switch kind {
        case .home:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.36),
                    Color(red: 0.44, green: 0.24, blue: 0.11).opacity(0.20),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .floor, .room, .container:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.48),
                    Color(red: 0.57, green: 0.35, blue: 0.16).opacity(0.12),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct CubbyWallBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [CubbyTheme.wallTop, CubbyTheme.wallMiddle, CubbyTheme.wallBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                ForEach(0..<14, id: \.self) { index in
                    Rectangle()
                        .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.14) : CubbyTheme.shelfShadow.opacity(0.06))
                        .frame(height: 1)
                    Spacer(minLength: 38)
                }
            }
            .opacity(0.78)

            WoodgrainOverlay(opacity: 0.06)
        }
        .ignoresSafeArea()
    }
}

struct CubbySheetBackground: View {
    var body: some View {
        ZStack {
            CubbyWallBackground()

            LinearGradient(
                colors: [
                    CubbyTheme.paper.opacity(0.34),
                    Color.white.opacity(0.10),
                    CubbyTheme.paperDeep.opacity(0.24),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct CubbySheetRowBackground: View {
    var prominence: Double = 1

    var body: some View {
        ZStack {
            CubbyTheme.paper.opacity(0.88 * prominence)
            CubbySurfaceBackground(kind: .container)
                .opacity(0.22 * prominence)
        }
    }
}

struct CubbySurfaceBackground: View {
    let kind: CubbySurfaceKind

    var body: some View {
        ZStack {
            CubbyTheme.surfaceGradient(for: kind)
            WoodgrainOverlay(opacity: kind == .home ? 0.12 : 0.055)
        }
    }
}

struct CubbyShelfLip: View {
    let kind: CubbySurfaceKind
    var height: CGFloat = 9

    var body: some View {
        CubbyTheme.shelfLip(for: kind)
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

struct WoodgrainOverlay: View {
    let opacity: Double

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let width = proxy.size.width
                let height = max(proxy.size.height, 1)
                for index in 0..<18 {
                    let y = height * CGFloat(index + 1) / 20
                    let lift = CGFloat((index % 3) - 1) * 4
                    path.move(to: CGPoint(x: -12, y: y))
                    path.addCurve(
                        to: CGPoint(x: width + 12, y: y + lift),
                        control1: CGPoint(x: width * 0.30, y: y - 7 + lift),
                        control2: CGPoint(x: width * 0.70, y: y + 8 - lift)
                    )
                }
            }
            .stroke(CubbyTheme.shelfShadow.opacity(opacity), lineWidth: 0.75)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func cubbyNavigationBarChrome() -> some View {
        self
            .toolbarBackground(CubbyTheme.surfaceGradient(for: .container), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .tint(CubbyTheme.green)
    }

    func cubbySheetChrome() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(CubbySheetBackground())
            .listSectionSpacing(14)
            .cubbyNavigationBarChrome()
    }

    func cubbySheetRows(prominence: Double = 1) -> some View {
        self
            .listRowBackground(CubbySheetRowBackground(prominence: prominence))
            .listRowSeparatorTint(CubbyTheme.floorBorder.opacity(0.68))
    }
}
