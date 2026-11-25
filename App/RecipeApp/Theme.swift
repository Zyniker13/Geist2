import Foundation
import RecipeCore
import SwiftUI

/// The app's two visual themes (M4.4): "Paper" (a warm off-white
/// canvas with a warm accent) and "Slate" (a dark slate canvas with a
/// cool accent).
///
/// The choice persists in `@AppStorage("theme")` on the store; views
/// read the resolved theme through the environment so every screen
/// picks it up from the root down.
@MainActor
final class ThemeStore: ObservableObject {
    /// The user's chosen theme name, persisted.
    @AppStorage("theme") var themeName: String = Theme.paper.name

    /// The resolved theme object.
    var theme: Theme {
        Theme(named: themeName)
    }
}

/// One theme: the colors a screen tints with.
struct Theme: Equatable, Sendable {
    /// Stable name for storage and menus.
    let name: String
    /// The canvas color behind lists.
    let canvas: Color
    /// The accent: stars, timer chips, check-off circles.
    let accent: Color
    /// The color behind cards in the editor.
    let card: Color
    /// The color scheme the theme implies: Slate is a dark theme.
    let scheme: ColorScheme

    static let paper = Theme(
        name: "Paper",
        canvas: Color(red: 0.98, green: 0.97, blue: 0.94),
        accent: Color(red: 0.80, green: 0.45, blue: 0.15),
        card: Color(red: 1.0, green: 1.0, blue: 1.0),
        scheme: .light)

    static let slate = Theme(
        name: "Slate",
        canvas: Color(red: 0.11, green: 0.13, blue: 0.16),
        accent: Color(red: 0.55, green: 0.75, blue: 0.85),
        card: Color(red: 0.18, green: 0.20, blue: 0.24),
        scheme: .dark)

    /// Resolve from a stored name; unknown names fall back to Paper.
    init(named: String) {
        self = Theme.all.first { $0.name == named } ?? Theme.paper
    }

    private init(name: String, canvas: Color, accent: Color, card: Color, scheme: ColorScheme) {
        self.name = name
        self.canvas = canvas
        self.accent = accent
        self.card = card
        self.scheme = scheme
    }

    /// Every theme, in menu order.
    static let all: [Theme] = [paper, slate]

    /// The labels the theme menu shows.
    var label: String { name }
}

extension View {
    /// Applies the theme: canvas background, accent tint and implied
    /// color scheme, from the app root down.
    func themed(_ theme: Theme) -> some View {
        self
            .tint(theme.accent)
            .preferredColorScheme(theme.scheme)
            .background(theme.canvas.ignoresSafeArea())
    }
}
