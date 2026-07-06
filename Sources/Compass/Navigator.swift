@MainActor
public protocol Navigator: AnyObject {
    func route<S: Screen>(to context: ScreenContext<S>, via transition: Transition, animated: Bool)
    func dismiss(animated: Bool, completion: (() -> Void)?)
    func dismiss<S: Screen>(to type: S.Type, animated: Bool) throws
    func dismiss<S: Screen>(to type: S.Type, matching predicate: (S) -> Bool, animated: Bool) throws
}

public extension Navigator {
    func route<S: Screen>(to context: ScreenContext<S>, via transition: Transition) {
        route(to: context, via: transition, animated: true)
    }

    func route<S: Screen>(to screen: S, via transition: Transition, animated: Bool) {
        route(to: ScreenContext(screen), via: transition, animated: animated)
    }

    func route<S: Screen>(to screen: S, via transition: Transition) {
        route(to: ScreenContext(screen), via: transition, animated: true)
    }

    func dismiss() {
        dismiss(animated: true, completion: nil)
    }

    func dismiss(animated: Bool) {
        dismiss(animated: animated, completion: nil)
    }

    func dismiss<S: Screen>(to type: S.Type) throws {
        try dismiss(to: type, animated: true)
    }

    func dismiss<S: Screen>(to type: S.Type, matching predicate: (S) -> Bool) throws {
        try dismiss(to: type, matching: predicate, animated: true)
    }
}
