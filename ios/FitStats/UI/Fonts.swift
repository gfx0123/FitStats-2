import SwiftUI
import UIKit

/// The app's rounded font, Fredoka (bundled, SIL Open Font License: Resources/Fonts/OFL.txt).
/// Widgets keep the system font: they don't bundle it.
enum Fredoka {
    static func name(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light: return "Fredoka-Light"
        case .medium: return "Fredoka-Medium"
        case .semibold: return "Fredoka-SemiBold"
        case .bold, .heavy, .black: return "Fredoka-Bold"
        default: return "Fredoka-Regular"
        }
    }

    /// The point size iOS uses for each text style at the default text size.
    static func size(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }

    static func uiFont(_ size: CGFloat, _ weight: Font.Weight) -> UIFont {
        UIFont(name: name(weight), size: size) ?? .systemFont(ofSize: size)
    }

    /// Navigation bar titles, tab bar labels and segmented controls are drawn by UIKit.
    static func applyToUIKit() {
        // Clear over the scene at the top of a screen, frosted once the content scrolls under it.
        func navBar(_ clear: Bool) -> UINavigationBarAppearance {
            let nav = UINavigationBarAppearance()
            if clear {
                nav.configureWithTransparentBackground()
            } else {
                nav.configureWithDefaultBackground()
                nav.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
                nav.backgroundColor = UIColor(red: 0.02, green: 0.07, blue: 0.08, alpha: 0.25)
            }
            nav.titleTextAttributes = [.font: uiFont(17, .semibold), .foregroundColor: UIColor.white]
            nav.largeTitleTextAttributes = [.font: uiFont(34, .semibold), .foregroundColor: UIColor.white]
            let button = UIBarButtonItemAppearance()
            button.normal.titleTextAttributes = [.font: uiFont(17, .medium)]
            nav.buttonAppearance = button
            nav.doneButtonAppearance = button
            nav.backButtonAppearance = button
            return nav
        }
        UINavigationBar.appearance().standardAppearance = navBar(false)
        UINavigationBar.appearance().compactAppearance = navBar(false)
        UINavigationBar.appearance().scrollEdgeAppearance = navBar(true)

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        tab.backgroundColor = UIColor(red: 0.02, green: 0.07, blue: 0.08, alpha: 0.35)
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.titleTextAttributes = [.font: uiFont(10, .medium)]
            item.selected.titleTextAttributes = [.font: uiFont(10, .semibold)]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        UISegmentedControl.appearance().setTitleTextAttributes([.font: uiFont(13, .medium)], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: uiFont(13, .semibold)], for: .selected)
    }
}

extension Font {
    /// Fredoka in place of a text style; grows with the iPhone's text size like the style does.
    static func fs(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        .custom(Fredoka.name(weight ?? (style == .headline ? .semibold : .regular)), size: Fredoka.size(style), relativeTo: style)
    }

    /// Fredoka at a fixed size (big numbers; in place of `.system(size:)`).
    static func fredoka(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom(Fredoka.name(weight), fixedSize: size)
    }
}
