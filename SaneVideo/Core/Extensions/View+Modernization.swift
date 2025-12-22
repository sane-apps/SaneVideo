import SwiftUI

extension View {
    /// Conditional modifier for modern macOS features
    @ViewBuilder
    func ifAvailable<Content: View>(@ViewBuilder _ transform: (Self) -> Content) -> some View {
        transform(self)
    }
}
