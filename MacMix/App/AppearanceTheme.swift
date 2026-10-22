//
//  AppearanceTheme.swift
//  MacMix
//

import AppKit
import SwiftUI

enum ThemePreference {
    static let accentColor = "MacMix.AccentColor"
    static let mainInterfaceBackgroundMaterial = "MacMix.MainInterfaceBackgroundMaterial"
}

enum MainInterfaceBackgroundMaterial: String, CaseIterable, Identifiable {
    case standard
    case ultraThick
    case thick
    case regular = "blur"
    case thin
    case ultraThin

    var id: Self { self }

    func resolved(hasStudioAccess: Bool) -> Self {
        hasStudioAccess ? self : .standard
    }

    var usesBlur: Bool {
        guard self != .standard else { return false }

        if #available(macOS 15.0, *) {
            return true
        }

        return false
    }

    var windowBackgroundStyle: AnyShapeStyle {
        switch self {
        case .standard:
            AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
        case .ultraThick:
            AnyShapeStyle(.ultraThickMaterial)
        case .thick:
            AnyShapeStyle(.thickMaterial)
        case .regular:
            AnyShapeStyle(.regularMaterial)
        case .thin:
            AnyShapeStyle(.thinMaterial)
        case .ultraThin:
            AnyShapeStyle(.ultraThinMaterial)
        }
    }

    var sliderPosition: Double {
        get {
            Double(Self.allCases.firstIndex(of: self) ?? 0)
        }
        set {
            let nearestIndex = min(
                max(Int(newValue.rounded()), Self.allCases.startIndex),
                Self.allCases.index(before: Self.allCases.endIndex)
            )
            self = Self.allCases[nearestIndex]
        }
    }
}

struct MainInterfaceWindowBackgroundModifier: ViewModifier {
    let style: AnyShapeStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.containerBackground(style, for: .window)
        } else {
            content
        }
    }
}

enum ThemeAccentColor: String, CaseIterable, Identifiable {
    case system
    case blue
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case gray

    var id: Self { self }

    func resolvedColor(hasStudioAccess: Bool) -> Color {
        hasStudioAccess ? color : Self.system.color
    }

    var color: Color {
        switch self {
        case .system:
            Color(nsColor: .controlAccentColor)
        case .blue:
            Color(nsColor: .systemBlue)
        case .purple:
            Color(nsColor: .systemPurple)
        case .pink:
            Color(
                .sRGB,
                red: 0.968627,
                green: 0.309804,
                blue: 0.619608
            )
        case .red:
            Color(nsColor: .systemRed)
        case .orange:
            Color(nsColor: .systemOrange)
        case .yellow:
            Color(nsColor: .systemYellow)
        case .green:
            Color(nsColor: .systemGreen)
        case .gray:
            Color(nsColor: .systemGray)
        }
    }

    var localizedName: LocalizedStringResource {
        switch self {
        case .system:
            "System"
        case .blue:
            "Blue"
        case .purple:
            "Purple"
        case .pink:
            "Pink"
        case .red:
            "Red"
        case .orange:
            "Orange"
        case .yellow:
            "Yellow"
        case .green:
            "Green"
        case .gray:
            "Gray"
        }
    }
}
