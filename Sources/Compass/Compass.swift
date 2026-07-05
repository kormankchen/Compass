import UIKit

@MainActor
public enum Compass {
    public static func configure<S: Screen>(
        root: S,
        modules: [any NavigatorModule.Type],
        in scene: UIWindowScene
    ) {
        let registry = MainRegistry()
        registry.register(modules: modules)
        let nav = MainNavigator(root: root, registry: registry)
        MainNavigator.instance = nav
        let window = UIWindow(windowScene: scene)
        window.rootViewController = nav.navController
        window.makeKeyAndVisible()
        nav.window = window
    }

    public static var shared: any Navigator {
        guard let nav = MainNavigator.instance else {
            fatalError("Compass.configure() must be called before accessing Compass.shared")
        }
        return nav
    }
}
