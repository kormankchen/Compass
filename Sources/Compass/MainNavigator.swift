import UIKit

@MainActor
final class MainNavigator: Navigator {

    static var instance: MainNavigator?

    let navController: UINavigationController
    var window: UIWindow?
    private var auxiliaryWindow: UIWindow?
    private let registry: MainRegistry
    private let navDelegate: NavigatorDelegate
    var vcScreenMap: [ObjectIdentifier: AnyHashable] = [:]

    init<S: Screen>(root: S, registry: MainRegistry) {
        guard let rootVC = registry.makeViewController(for: root) else {
            fatalError("No factory registered for \(type(of: root)). Register it in a NavigatorModule.")
        }
        self.registry = registry
        navController = UINavigationController(rootViewController: rootVC)
        let del = NavigatorDelegate()
        navDelegate = del
        del.owner = self
        vcScreenMap[ObjectIdentifier(rootVC)] = AnyHashable(root)
    }

    // MARK: - Traversal Helpers

    private var activeNavController: UINavigationController {
        let startNav: UINavigationController
        if let aux = auxiliaryWindow, aux.isKeyWindow,
           let auxNav = aux.rootViewController as? UINavigationController {
            startNav = auxNav
        } else {
            startNav = navController
        }
        var current: UIViewController = startNav
        while let presented = current.presentedViewController { current = presented }
        return (current as? UINavigationController) ?? startNav
    }

    private func collectNavControllerChain() -> [UINavigationController] {
        var chain: [UINavigationController] = []
        var current: UIViewController? = navController
        while let vc = current {
            if let nav = vc as? UINavigationController { chain.append(nav) }
            current = vc.presentedViewController
        }
        if let aux = auxiliaryWindow,
           let auxNav = aux.rootViewController as? UINavigationController {
            var auxCurrent: UIViewController? = auxNav
            while let vc = auxCurrent {
                if let nav = vc as? UINavigationController { chain.append(nav) }
                auxCurrent = vc.presentedViewController
            }
        }
        return chain
    }

    func collectAllVCs() -> [UIViewController] {
        collectNavControllerChain().flatMap { $0.viewControllers }
    }

    private func isInAuxiliaryHierarchy(_ nav: UINavigationController) -> Bool {
        var current: UIViewController? = auxiliaryWindow?.rootViewController
        while let vc = current {
            if vc === nav { return true }
            current = vc.presentedViewController
        }
        return false
    }

    // MARK: - Navigator

    func route<S: Screen>(to screen: S, via transition: Transition, animated: Bool) {
        guard let vc = registry.makeViewController(for: screen) else {
            fatalError("No factory registered for \(type(of: screen)). Register it in a NavigatorModule.")
        }
        vcScreenMap[ObjectIdentifier(vc)] = AnyHashable(screen)

        switch transition {
        case .push:
            activeNavController.pushViewController(vc, animated: animated)

        case .sheet, .fullScreen, .overFullScreen:
            let childNav = UINavigationController(rootViewController: vc)
            childNav.modalPresentationStyle = transition.uiKitStyle
            activeNavController.present(childNav, animated: animated) {
                childNav.presentationController?.delegate = self.navDelegate
            }

        case .newWindow:
            guard let scene = window?.windowScene else {
                assertionFailure("Compass: no UIWindowScene available for newWindow transition")
                return
            }
            let childNav = UINavigationController(rootViewController: vc)
            let aux = UIWindow(windowScene: scene)
            aux.rootViewController = childNav
            aux.windowLevel = .alert
            auxiliaryWindow = aux
            let auxID = ObjectIdentifier(aux)
            NotificationCenter.default.addObserver(
                forName: UIWindow.didBecomeHiddenNotification,
                object: aux,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self,
                          let current = self.auxiliaryWindow,
                          ObjectIdentifier(current) == auxID else { return }
                    self.auxiliaryWindow = nil
                    let liveIDs = Set(self.collectAllVCs().map { ObjectIdentifier($0) })
                    self.vcScreenMap = self.vcScreenMap.filter { liveIDs.contains($0.key) }
                }
            }
            aux.makeKeyAndVisible()
        }
    }

    func dismiss(animated: Bool) {
        let active = activeNavController
        if active.viewControllers.count > 1 {
            active.popViewController(animated: animated)
        } else if let aux = auxiliaryWindow, isInAuxiliaryHierarchy(active) {
            aux.isHidden = true
            auxiliaryWindow = nil
            window?.makeKey()
        } else if active !== navController {
            active.dismiss(animated: animated)
        }
    }

    func dismiss<S: Screen>(to type: S.Type, animated: Bool) throws {
        try dismiss(to: type, matching: { _ in true }, animated: animated)
    }

    func dismiss<S: Screen>(to type: S.Type, matching predicate: (S) -> Bool, animated: Bool) throws {
        let targetTypeID = ObjectIdentifier(type)

        for nav in collectNavControllerChain() {
            for vc in nav.viewControllers {
                guard let entry = vcScreenMap[ObjectIdentifier(vc)],
                      let screen = entry.base as? S,
                      ObjectIdentifier(Swift.type(of: screen)) == targetTypeID,
                      predicate(screen) else { continue }

                let targetVC = vc

                if !isInAuxiliaryHierarchy(nav), let aux = auxiliaryWindow {
                    aux.isHidden = true
                    auxiliaryWindow = nil
                    window?.makeKey()
                }

                if nav.presentedViewController != nil {
                    nav.dismiss(animated: animated) {
                        nav.popToViewController(targetVC, animated: false)
                    }
                } else {
                    nav.popToViewController(targetVC, animated: animated)
                }
                return
            }
        }
        throw NavigationError.screenNotFound
    }
}

// MARK: - NavigatorDelegate

@MainActor
final class NavigatorDelegate: NSObject, UIAdaptivePresentationControllerDelegate {
    weak var owner: MainNavigator?

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let owner else { return }
        let liveIDs = Set(owner.collectAllVCs().map { ObjectIdentifier($0) })
        owner.vcScreenMap = owner.vcScreenMap.filter { liveIDs.contains($0.key) }
    }
}
