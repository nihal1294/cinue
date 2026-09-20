import SwiftUI

enum CinueIconTone {
    case primary
    case cloud
    case privacy
    case metadata
    case importExport
    case diagnostics
    case neutral

    var accent: Color {
        switch self {
        case .primary:
            CinueColors.accentBlue
        case .cloud:
            CinueColors.brandTeal
        case .privacy:
            CinueColors.watchedGreen
        case .metadata:
            CinueColors.reminderAmber
        case .importExport:
            CinueColors.coral
        case .diagnostics:
            CinueColors.brandTeal
        case .neutral:
            CinueColors.lightTextSecondary
        }
    }
}

enum CinueIconMetrics {
    static let usesLiquidGlassPlates = true
    static let darkPlateTintOpacity = 0.08
    static let lightPlateTintOpacity = 0.14
}

struct CinueIconTile: View {
    @Environment(\.colorScheme) private var colorScheme

    let symbol: String
    var tone: CinueIconTone = .primary
    var size: CGFloat = 34

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            plate

            Image(systemName: symbol)
                .font(.system(size: size * 0.45, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tone.accent)
                .frame(width: size, height: size)

            CinueIconNode(tone: tone, size: size * 0.32)
                .offset(x: size * 0.07, y: size * 0.07)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var plate: some View {
        let cornerRadius = size * 0.28
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26, *) {
            shape
                .fill(plateTint)
                .glassEffect(.regular.tint(plateTint), in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    shape.stroke(borderColor, lineWidth: 0.7)
                }
                .overlay {
                    CinueGlassReflectionOverlay(cornerRadius: cornerRadius, opacity: reflectionOpacity)
                }
        } else {
            shape
                .fill(.ultraThinMaterial)
                .background(plateTint, in: shape)
                .overlay {
                    shape.stroke(borderColor, lineWidth: 0.7)
                }
                .overlay {
                    CinueGlassReflectionOverlay(cornerRadius: cornerRadius, opacity: reflectionOpacity)
                }
        }
    }

    private var plateTint: Color {
        colorScheme == .dark
            ? .white.opacity(CinueIconMetrics.darkPlateTintOpacity)
            : .white.opacity(CinueIconMetrics.lightPlateTintOpacity)
    }

    private var borderColor: Color {
        colorScheme == .dark ? .white.opacity(0.18) : tone.accent.opacity(0.18)
    }

    private var reflectionOpacity: Double {
        colorScheme == .dark
            ? CinueGlassSurfaceMetrics.darkReflectionOpacity
            : CinueGlassSurfaceMetrics.lightReflectionOpacity
    }
}

private struct CinueIconNode: View {
    @Environment(\.colorScheme) private var colorScheme

    let tone: CinueIconTone
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(nodeBackground)
                .overlay {
                    Circle()
                        .stroke(nodeBorder, lineWidth: 0.6)
                }

            Circle()
                .fill(tone.accent)
                .frame(width: size * 0.38, height: size * 0.38)
        }
        .frame(width: size, height: size)
    }

    private var nodeBackground: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .white.opacity(0.72)
    }

    private var nodeBorder: Color {
        colorScheme == .dark ? .white.opacity(0.14) : tone.accent.opacity(0.28)
    }
}

struct CinueSettingsRow: View {
    let title: String
    let symbol: String
    var tone: CinueIconTone = .primary

    var body: some View {
        HStack(spacing: CinueSpacing.md) {
            CinueIconTile(symbol: symbol, tone: tone, size: 32)

            Text(title)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

struct CinueNavigationRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let symbol: String
    var tone: CinueIconTone = .primary
    var isSelected = false

    var body: some View {
        HStack(spacing: CinueSpacing.md) {
            CinueIconTile(symbol: symbol, tone: tone, size: 28)

            Text(title)
                .foregroundStyle(textColor)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, CinueSpacing.sm)
        .padding(.vertical, CinueSpacing.xs)
        .cinueGlassControl(
            cornerRadius: CinueRadius.sm,
            tone: tone,
            interactive: true,
            isSelected: isSelected
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    private var textColor: Color {
        if isSelected {
            return colorScheme == .dark ? CinueColors.textPrimary : CinueColors.lightTextPrimary
        }

        return colorScheme == .dark ? CinueColors.textSecondary : CinueColors.lightTextPrimary
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 14) {
        CinueSettingsRow(title: "iCloud Sync", symbol: "icloud.fill", tone: .cloud)
        CinueSettingsRow(title: "Import and Export", symbol: "arrow.down.doc.fill", tone: .importExport)
        CinueSettingsRow(title: "Privacy", symbol: "lock.shield.fill", tone: .privacy)
        CinueSettingsRow(title: "Provider Keys", symbol: "key.fill", tone: .metadata)
        CinueNavigationRow(title: "Now", symbol: "bookmark.fill", tone: .primary, isSelected: true)
    }
    .padding()
}
