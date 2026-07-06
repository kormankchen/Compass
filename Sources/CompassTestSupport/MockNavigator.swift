import Compass

@MainActor
public final class MockNavigator: Navigator {

    public struct RouteCall {
        public let screen: AnyHashable
        public let transition: Transition
        public let animated: Bool
    }

    public var routeCalls: [RouteCall] = []
    public var dismissCount: Int = 0
    public var lastDismissType: Any.Type?

    public init() {}

    public func route<S: Screen>(to context: ScreenContext<S>, via transition: Transition, animated: Bool) {
        routeCalls.append(RouteCall(screen: AnyHashable(context.screen), transition: transition, animated: animated))
    }

    public func dismiss(animated: Bool, completion: (() -> Void)?) {
        dismissCount += 1
        completion?()
    }

    public func dismiss<S: Screen>(to type: S.Type, animated: Bool) throws {
        lastDismissType = type
    }

    public func dismiss<S: Screen>(to type: S.Type, matching predicate: (S) -> Bool, animated: Bool) throws {
        lastDismissType = type
    }
}
