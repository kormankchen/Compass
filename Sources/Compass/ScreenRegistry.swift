import UIKit

public protocol ScreenRegistry: AnyObject {
    func register<S: Screen>(_ type: S.Type, factory: @escaping @MainActor (ScreenContext<S>) -> UIViewController)
}

public protocol NavigatorModule {
    static func register(in registry: any ScreenRegistry)
}

final class MainRegistry: ScreenRegistry {
    private var factories: [ObjectIdentifier: @MainActor (AnyObject) -> UIViewController] = [:]

    func register<S: Screen>(_ type: S.Type, factory: @escaping @MainActor (ScreenContext<S>) -> UIViewController) {
        factories[ObjectIdentifier(type)] = { anyContext in
            guard let context = anyContext as? ScreenContext<S> else {
                fatalError("Compass internal error: type mismatch for \(type)")
            }
            return factory(context)
        }
    }

    func register(modules: [any NavigatorModule.Type]) {
        modules.forEach { $0.register(in: self) }
    }

    @MainActor
    func makeViewController<S: Screen>(for context: ScreenContext<S>) -> UIViewController? {
        factories[ObjectIdentifier(S.self)]?(context)
    }
}
