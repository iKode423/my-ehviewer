import SwiftUI

/// Arranges child views in wrapping rows for compact tag displays.
struct FlowLayout: Layout {
    let spacing: CGFloat

    /// Calculates the total size needed for all subviews.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        return layout(subviews: subviews, maxWidth: width).size
    }

    /// Places subviews in rows that wrap at the proposed width.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, maxWidth: bounds.width)
        for item in result.items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
            )
        }
    }

    /// Computes row positions without mutating the subviews.
    private func layout(subviews: Subviews, maxWidth: CGFloat) -> LayoutResult {
        var items: [LayoutItem] = []
        var cursor = CGPoint.zero
        var rowHeight: CGFloat = 0
        let availableWidth = max(maxWidth, 1)

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > availableWidth {
                cursor.x = 0
                cursor.y += rowHeight + spacing
                rowHeight = 0
            }

            items.append(LayoutItem(index: index, origin: cursor, size: size))
            cursor.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return LayoutResult(size: CGSize(width: availableWidth, height: cursor.y + rowHeight), items: items)
    }

    /// Stores one placed subview.
    private struct LayoutItem {
        let index: Int
        let origin: CGPoint
        let size: CGSize
    }

    /// Stores the full layout calculation.
    private struct LayoutResult {
        let size: CGSize
        let items: [LayoutItem]
    }
}
