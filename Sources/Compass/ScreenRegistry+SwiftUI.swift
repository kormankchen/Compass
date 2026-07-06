import SwiftUI

extension ScreenRegistry {
    public func register<S: Screen, V: View>(
        _ type: S.Type,
        @ViewBuilder view: @escaping @MainActor (S) -> V
    ) {
        register(type) { context in UIHostingController(rootView: view(context.screen)) }
    }
}
