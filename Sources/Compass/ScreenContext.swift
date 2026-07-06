@MainActor
public final class ScreenContext<S: Screen> {
    public let screen: S

    public init(_ screen: S) { self.screen = screen }

    public func addObservation(_ events: NavigationEvent...) {
        for event in events {
            switch event {
            case .shouldDismiss(let handler):
                shouldDismissHandlers.append(handler)
            case .didDismiss(let handler):
                didDismissHandlers.append(handler)
            }
        }
    }

    private var shouldDismissHandlers: [@MainActor () -> Bool] = []
    private var didDismissHandlers: [@MainActor () -> Void] = []
}

@MainActor
protocol AnyScreenContext: AnyObject {
    func evaluateShouldDismiss() -> Bool
    func notifyDidDismiss()
}

extension ScreenContext: AnyScreenContext {
    func evaluateShouldDismiss() -> Bool {
        shouldDismissHandlers.isEmpty || shouldDismissHandlers.allSatisfy { $0() }
    }

    func notifyDidDismiss() {
        didDismissHandlers.forEach { $0() }
    }
}
