import SwiftUI
import UIKit

enum CubbySurfaceKind {
    case home
    case floor
    case room
    case container
}

enum CubbyTheme {
    // The palette deliberately feels residential rather than "productivity blue":
    // warm plaster, walnut, canvas, and a calm evergreen action color.
    static let wallTop = Color(red: 0.985, green: 0.965, blue: 0.925)
    static let wallMiddle = Color(red: 0.945, green: 0.895, blue: 0.815)
    static let wallBottom = Color(red: 0.885, green: 0.795, blue: 0.675)
    static let warmInk = Color(red: 0.13, green: 0.105, blue: 0.085)
    static let mutedInk = Color(red: 0.36, green: 0.315, blue: 0.27)
    static let green = Color(red: 0.19, green: 0.36, blue: 0.31)
    static let greenRaised = Color(red: 0.24, green: 0.43, blue: 0.37)
    static let greenSoft = Color(red: 0.84, green: 0.90, blue: 0.86)
    static let amber = Color(red: 0.56, green: 0.27, blue: 0.07)
    static let amberSoft = Color(red: 0.96, green: 0.85, blue: 0.70)
    static let danger = Color(red: 0.69, green: 0.18, blue: 0.16)
    static let paper = Color(red: 0.995, green: 0.982, blue: 0.945)
    static let paperDeep = Color(red: 0.91, green: 0.85, blue: 0.75)
    static let shelfShadow = Color(red: 0.20, green: 0.135, blue: 0.085)
    static let darkWoodTop = Color(red: 0.40, green: 0.255, blue: 0.17)
    static let darkWoodMiddle = Color(red: 0.27, green: 0.165, blue: 0.105)
    static let darkWoodBottom = Color(red: 0.13, green: 0.075, blue: 0.045)
    static let homeBorder = Color(red: 0.34, green: 0.22, blue: 0.14).opacity(0.30)
    static let floorBorder = Color(red: 0.39, green: 0.285, blue: 0.19).opacity(0.21)
    static let roomBorder = Color(red: 0.42, green: 0.32, blue: 0.23).opacity(0.16)
    static let containerBorder = Color(red: 0.38, green: 0.30, blue: 0.22).opacity(0.14)

    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let standard: CGFloat = 16
        static let large: CGFloat = 20
        static let section: CGFloat = 28
    }

    enum Radius {
        static let control: CGFloat = 14
        static let card: CGFloat = 18
        static let hero: CGFloat = 24
    }

    static var navigationWoodGradient: LinearGradient {
        LinearGradient(
            colors: [darkWoodTop, darkWoodMiddle, darkWoodBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var navigationWallGradient: LinearGradient {
        LinearGradient(
            colors: [paper.opacity(0.98), wallTop.opacity(0.96), wallMiddle.opacity(0.88)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var actionGradient: LinearGradient {
        LinearGradient(
            colors: [greenRaised, green, Color(red: 0.12, green: 0.25, blue: 0.21)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var navigationCellGradient: LinearGradient {
        LinearGradient(
            colors: [
                paper,
                paperDeep.opacity(0.72),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func surfaceGradient(for kind: CubbySurfaceKind) -> LinearGradient {
        switch kind {
        case .home:
            return LinearGradient(
                colors: [
                    Color(red: 0.90, green: 0.77, blue: 0.60),
                    Color(red: 0.80, green: 0.62, blue: 0.43),
                    Color(red: 0.69, green: 0.48, blue: 0.31),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .floor:
            return LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.91, blue: 0.80),
                    Color(red: 0.88, green: 0.76, blue: 0.59),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .room:
            return LinearGradient(
                colors: [
                    Color(red: 0.995, green: 0.975, blue: 0.92),
                    Color(red: 0.93, green: 0.87, blue: 0.77),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .container:
            return LinearGradient(
                colors: [
                    paper,
                    Color(red: 0.93, green: 0.89, blue: 0.81),
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
                    Color.white.opacity(0.30),
                    shelfShadow.opacity(0.22),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .floor, .room, .container:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.42),
                    shelfShadow.opacity(0.12),
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

            RadialGradient(
                colors: [Color.white.opacity(0.38), .clear],
                center: UnitPoint(x: 0.18, y: 0.04),
                startRadius: 8,
                endRadius: 390
            )

            RadialGradient(
                colors: [CubbyTheme.green.opacity(0.055), .clear],
                center: UnitPoint(x: 0.94, y: 0.72),
                startRadius: 12,
                endRadius: 440
            )

            VStack(spacing: 0) {
                ForEach(0..<11, id: \.self) { index in
                    Rectangle()
                        .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.12) : CubbyTheme.shelfShadow.opacity(0.035))
                        .frame(height: 0.5)
                    Spacer(minLength: 52)
                }
            }
            .opacity(0.62)

            WoodgrainOverlay(opacity: 0.032)
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
                    Color.white.opacity(0.30),
                    CubbyTheme.paper.opacity(0.20),
                    CubbyTheme.greenSoft.opacity(0.12),
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
            CubbyTheme.paper.opacity(0.94 * prominence)
            LinearGradient(
                colors: [Color.white.opacity(0.30 * prominence), CubbyTheme.paperDeep.opacity(0.12 * prominence)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct CubbySurfaceBackground: View {
    let kind: CubbySurfaceKind

    var body: some View {
        ZStack {
            CubbyTheme.surfaceGradient(for: kind)
            LinearGradient(
                colors: [Color.white.opacity(kind == .home ? 0.14 : 0.22), .clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            WoodgrainOverlay(opacity: kind == .home ? 0.075 : 0.03)
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

struct CubbyWoodButtonFill<Shape: InsettableShape>: View {
    let shape: Shape

    var body: some View {
        ZStack {
            shape.fill(CubbyTheme.actionGradient)
            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.18),
                        Color.white.opacity(0.02),
                        Color.black.opacity(0.16),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .clipShape(shape)
    }
}

struct CubbyWoodButtonSurfaceModifier: ViewModifier {
    var isEnabled: Bool = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: CubbyTheme.Radius.control, style: .continuous)

        content
            .foregroundStyle(Color.white)
            .background {
                CubbyWoodButtonFill(shape: shape)
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
            }
            .shadow(color: CubbyTheme.green.opacity(isEnabled ? 0.18 : 0), radius: 10, y: 5)
            .opacity(isEnabled ? 1 : 0.48)
            .contentShape(shape)
    }
}

struct CubbyWoodTextButtonLabel: View {
    let title: String
    var width: CGFloat? = nil

    var body: some View {
        let shape = Capsule(style: .continuous)

        Text(title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(width: width)
            .frame(minHeight: 44)
            .padding(.horizontal, width == nil ? 18 : 0)
            .background {
                CubbyWoodButtonFill(shape: shape)
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
            }
            .shadow(color: CubbyTheme.green.opacity(0.18), radius: 10, y: 5)
            .contentShape(shape)
    }
}

struct CubbyStatusPill: View {
    let title: String
    let systemImage: String
    var tint = CubbyTheme.green

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.10), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 0.75)
            }
    }
}

private struct CubbyPanelSurfaceModifier: ViewModifier {
    var padding: CGFloat
    var cornerRadius: CGFloat
    var elevated: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape
                    .fill(CubbyTheme.paper.opacity(0.94))
                    .overlay {
                        LinearGradient(
                            colors: [Color.white.opacity(0.42), CubbyTheme.greenSoft.opacity(0.08), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(shape)
                    }
            }
            .overlay {
                shape.stroke(CubbyTheme.floorBorder.opacity(0.74), lineWidth: 0.75)
            }
            .shadow(
                color: elevated ? CubbyTheme.shelfShadow.opacity(0.14) : .clear,
                radius: elevated ? 20 : 0,
                y: elevated ? 10 : 0
            )
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

struct CubbyNavigationBrandTitle: View {
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            CubbyBrandMark()

            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(CubbyTheme.warmInk)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

struct CubbyBrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)

        ZStack {
            shape
                .fill(CubbyTheme.navigationWoodGradient)

            WoodgrainOverlay(opacity: 0.18)
                .clipShape(shape)

            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.32),
                            Color.white.opacity(0.08),
                            CubbyTheme.shelfShadow.opacity(0.22),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: size * 0.071) {
                HStack(spacing: size * 0.071) {
                    CubbyNavigationCell(accent: CubbyTheme.green, scale: size / 28)
                    CubbyNavigationCell(accent: CubbyTheme.paperDeep, scale: size / 28)
                }

                HStack(spacing: size * 0.071) {
                    CubbyNavigationCell(accent: CubbyTheme.amber, scale: size / 28)
                    CubbyNavigationCell(accent: CubbyTheme.paper, scale: size / 28)
                }
            }
            .padding(size * 0.14)
        }
        .frame(width: size, height: size)
        .overlay(shape.stroke(Color.white.opacity(0.24), lineWidth: 0.75))
        .shadow(color: CubbyTheme.shelfShadow.opacity(0.24), radius: size * 0.15, y: size * 0.07)
        .accessibilityHidden(true)
    }
}

private struct CubbyNavigationCell: View {
    let accent: Color
    let scale: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5 * scale, style: .continuous)
            .fill(CubbyTheme.navigationCellGradient)
            .overlay(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 1.5 * scale, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent,
                                accent.opacity(0.52),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 5 * scale, height: 5 * scale)
                    .padding(1.5 * scale)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 2.5 * scale, style: .continuous)
                    .stroke(CubbyTheme.shelfShadow.opacity(0.22), lineWidth: 0.5 * scale)
            }
    }
}

private struct CubbyNavigationTitleModifier: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .principal) {
                    CubbyNavigationBrandTitle(title: title)
                }
            }
    }
}

private struct CubbyNavigationBarSeparatorInstaller: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.installSeparator()
    }

    final class Controller: UIViewController {
        private var didScheduleRetry = false

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            installSeparator()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            installSeparator()
        }

        func installSeparator() {
            guard let navigationBar = navigationController?.navigationBar else {
                guard !didScheduleRetry else { return }
                didScheduleRetry = true
                DispatchQueue.main.async { [weak self] in
                    self?.didScheduleRetry = false
                    self?.installSeparator()
                }
                return
            }

            didScheduleRetry = false
            let separator = UIColor(red: 0.24, green: 0.16, blue: 0.10, alpha: 0.18)
            navigationBar.standardAppearance = navigationBar.standardAppearance.withCubbySeparator(separator)
            navigationBar.scrollEdgeAppearance = (navigationBar.scrollEdgeAppearance ?? navigationBar.standardAppearance)
                .withCubbySeparator(separator)
            navigationBar.compactAppearance = (navigationBar.compactAppearance ?? navigationBar.standardAppearance)
                .withCubbySeparator(separator)

            if #available(iOS 15.0, *) {
                navigationBar.compactScrollEdgeAppearance = (
                    navigationBar.compactScrollEdgeAppearance ?? navigationBar.scrollEdgeAppearance ?? navigationBar.standardAppearance
                )
                .withCubbySeparator(separator)
            }
        }
    }
}

private extension UINavigationBarAppearance {
    func withCubbySeparator(_ color: UIColor) -> UINavigationBarAppearance {
        let appearance = copy() as! UINavigationBarAppearance
        appearance.shadowColor = color
        appearance.shadowImage = nil
        return appearance
    }
}

extension View {
    func cubbyWoodButtonSurface(isEnabled: Bool = true) -> some View {
        modifier(CubbyWoodButtonSurfaceModifier(isEnabled: isEnabled))
    }

    func cubbyPanel(
        padding: CGFloat = CubbyTheme.Spacing.standard,
        cornerRadius: CGFloat = CubbyTheme.Radius.card,
        elevated: Bool = false
    ) -> some View {
        modifier(CubbyPanelSurfaceModifier(padding: padding, cornerRadius: cornerRadius, elevated: elevated))
    }

    func cubbyNavigationBarChrome() -> some View {
        self
            .toolbarBackground(CubbyTheme.navigationWallGradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .tint(CubbyTheme.warmInk)
            .background(CubbyNavigationBarSeparatorInstaller())
    }

    func cubbyNavigationBarChrome(title: String) -> some View {
        self
            .navigationTitle("")
            .cubbyNavigationBarChrome()
            .cubbyNavigationTitle(title)
    }

    func cubbyNavigationTitle(_ title: String) -> some View {
        self
            .modifier(CubbyNavigationTitleModifier(title: title))
    }

    func cubbySheetChrome() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(CubbySheetBackground())
            .listSectionSpacing(14)
            .cubbyNavigationBarChrome()
    }

    func cubbySheetChrome(title: String) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(CubbySheetBackground())
            .listSectionSpacing(14)
            .cubbyNavigationBarChrome(title: title)
    }

    func cubbySheetRows(prominence: Double = 1) -> some View {
        self
            .listRowBackground(CubbySheetRowBackground(prominence: prominence))
            .listRowSeparatorTint(CubbyTheme.floorBorder.opacity(0.68))
    }
}
