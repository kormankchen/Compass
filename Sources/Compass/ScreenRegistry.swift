import UIKit

public protocol ScreenRegistry: AnyObject {
    func register<S: Screen>(_ type: S.Type, factory: @escaping @MainActor (S) -> UIViewController)
}

public protocol NavigatorModule {
    static func register(in registry: any ScreenRegistry)
}

final class MainRegistry: ScreenRegistry {
    private var factories: [ObjectIdentifier: @MainActor (AnyHashable) -> UIViewController] = [:]

    func register<S: Screen>(_ type: S.Type, factory: @escaping @MainActor (S) -> UIViewController) {
        factories[ObjectIdentifier(type)] = { anyScreen in
            guard let screen = anyScreen.base as? S else {
                fatalError("Compass internal error: type mismatch for \(type)")
            }
            return factory(screen)
        }
    }

    func register(modules: [any NavigatorModule.Type]) {
        modules.forEach { $0.register(in: self) }
    }

    @MainActor
    func makeViewController<S: Screen>(for screen: S) -> UIViewController? {
        factories[ObjectIdentifier(S.self)]?(AnyHashable(screen))
    }
}
