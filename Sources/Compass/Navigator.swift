@MainActor
public protocol Navigator: AnyObject {
    func route<S: Screen>(to screen: S, via transition: Transition, animated: Bool)
    func dismiss(animated: Bool)
    func dismiss<S: Screen>(to type: S.Type, animated: Bool) throws
    func dismiss<S: Screen>(to type: S.Type, matching predicate: (S) -> Bool, animated: Bool) throws
}

public extension Navigator {
    func route<S: Screen>(to screen: S, via transition: Transition) {
        route(to: screen, via: transition, animated: true)
    }

    func dismiss() {
        dismiss(animated: true)
    }

    func dismiss<S: Screen>(to type: S.Type) throws {
        try dismiss(to: type, animated: true)
    }

    func dismiss<S: Screen>(to type: S.Type, matching predicate: (S) -> Bool) throws {
        try dismiss(to: type, matching: predicate, animated: true)
    }
}
