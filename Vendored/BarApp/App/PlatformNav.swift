import SwiftUI

extension View {
    /// `navigationBarTitleDisplayMode` is iOS-only; macOS titles are already
    /// inline, so the modifier is a no-op there.
    @ViewBuilder
    func inlineNavTitle() -> some View {
        #if os(macOS)
            self
        #else
            navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

extension ToolbarItemPlacement {
    /// The trailing toolbar area for a group of sibling tools. On iOS this
    /// is `.topBarTrailing`: a group there keeps its children in the
    /// accessibility tree, while `.secondaryAction` inside a group leaves
    /// them out of it on the CI runtime. `.topBarTrailing` itself is
    /// unavailable on macOS, where `.secondaryAction` renders the group.
    static var trailingTools: ToolbarItemPlacement {
        #if os(macOS)
            .secondaryAction
        #else
            .topBarTrailing
        #endif
    }
}
