import SwiftUI

enum TrackingCategory: String, CaseIterable, Identifiable {
    case strength = "Krafttraining"
    case runs = "Läufe"
    case steps = "Steps"
    case weight = "Gewicht"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .runs: return "figure.run"
        case .steps: return "shoeprints.fill"
        case .weight: return "scalemass.fill"
        }
    }
}

struct TrackingCategoryCard: View {
    let category: TrackingCategory
    let primary: String
    let secondary: String
    var accent: Bool = false
    var showsChevron: Bool = true
    var minContentHeight: CGFloat = 72
    var dashboardEmphasis: Bool = false
    var primaryColor: Color? = nil
    var iconAccent: Bool? = nil

    var body: some View {
        LockedCard {
            HStack(spacing: dashboardEmphasis ? 16 : 14) {
                let useIconAccent = iconAccent ?? accent
                Image(systemName: category.icon)
                    .font(dashboardEmphasis ? .title.weight(.semibold) : .title3.weight(.semibold))
                    .foregroundStyle(useIconAccent ? Color.lockedGreen : .secondary)
                    .frame(
                        width: dashboardEmphasis ? 62 : 44,
                        height: dashboardEmphasis ? 62 : 44
                    )
                    .background((useIconAccent ? Color.lockedGreen : Color.white).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: dashboardEmphasis ? 16 : 12, style: .continuous))

                VStack(alignment: .leading, spacing: dashboardEmphasis ? 7 : 5) {
                    Text(category.rawValue.uppercased())
                        .font((dashboardEmphasis ? Font.caption : Font.caption2).weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(primary)
                        .font(dashboardEmphasis ? .title2.bold() : .title3.bold())
                        .foregroundStyle(primaryColor ?? (accent ? Color.lockedGreen : Color.primary))

                    Text(secondary)
                        .font(dashboardEmphasis ? .subheadline : .caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font((dashboardEmphasis ? Font.subheadline : Font.caption).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: minContentHeight, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}
