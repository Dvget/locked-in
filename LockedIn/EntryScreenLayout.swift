import SwiftUI

struct EntryScreenLayout<Content: View>: View {
    let cardCount: Int
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let spacing: CGFloat
    let content: (CGFloat) -> Content

    init(
        cardCount: Int = 4,
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 12,
        spacing: CGFloat = 12,
        @ViewBuilder content: @escaping (CGFloat) -> Content
    ) {
        self.cardCount = cardCount
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        GeometryReader { geo in
            let usableHeight = max(
                0,
                geo.size.height
                    - verticalPadding * 2
                    - spacing * CGFloat(max(0, cardCount - 1))
            )
            let outerCardHeight = cardCount > 0 ? usableHeight / CGFloat(cardCount) : 0
            let contentHeight = max(72, outerCardHeight - 32)

            VStack(spacing: spacing) {
                content(contentHeight)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color.black)
    }
}
