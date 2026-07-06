import UIKit

@MainActor
final class MainNavigator: Navigator {

    static var instance: MainNavigator?

    let navController: UINavigationController
    var window: UIWindow?
    private var auxiliaryWindow: UIWindow?
    // Bug 1 fix: retain the observer token so it can be removed.
    private var auxiliaryWindowObserver: NSObjectProtocol?
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

    // Called by Compass.configure before replacing the singleton so observers are always removed.
    func cleanup() {
        dismissAuxiliaryWindow()
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

    // Bug 4 fix: put the active window's chain first so dismiss(to:) searches the active context first.
    private func collectNavControllerChain() -> [UINavigationController] {
        let primaryRoot: UIViewController?
        let secondaryRoot: UIViewController?
        if let aux = auxiliaryWindow, aux.isKeyWindow {
            primaryRoot = aux.rootViewController
            secondaryRoot = navController
        } else {
            primaryRoot = navController
            secondaryRoot = auxiliaryWindow?.rootViewController
        }

        var chain: [UINavigationController] = []
        func walk(_ root: UIViewController?) {
            var current = root
            while let vc = current {
                if let nav = vc as? UINavigationController { chain.append(nav) }
                current = vc.presentedViewController
            }
        }
        walk(primaryRoot)
        walk(secondaryRoot)
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

    // Bug 1 & 2 fix: single place that removes the observer, hides the window, and cleans up the map.
    // Removing the observer BEFORE setting isHidden means the notification won't reach the external
    // dismissal path — no double-cleanup.
    private func dismissAuxiliaryWindow() {
        if let token = auxiliaryWindowObserver {
            NotificationCenter.default.removeObserver(token)
            auxiliaryWindowObserver = nil
        }
        auxiliaryWindow?.isHidden = true
        auxiliaryWindow = nil
        window?.makeKey()
        let liveIDs = Set(collectAllVCs().map { ObjectIdentifier($0) })
        vcScreenMap = vcScreenMap.filter { liveIDs.contains($0.key) }
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
            // Bug 3 fix: set the delegate synchronously after present — UIKit creates the
            // presentationController during the present call, so it is non-nil immediately.
            // Setting it in the completion block meant shouldDismiss/willDismiss never fired.
            activeNavController.present(childNav, animated: animated)
            childNav.presentationController?.delegate = navDelegate

        case .newWindow:
            guard let scene = window?.windowScene else {
                assertionFailure("Compass: no UIWindowScene available for newWindow transition")
                return
            }
            // Bug 2 fix: dismiss any existing aux window before creating a new one.
            // dismissAuxiliaryWindow() removes its observer first, so hiding it won't
            // re-trigger the external-dismissal path below.
            if auxiliaryWindow != nil { dismissAuxiliaryWindow() }

            let childNav = UINavigationController(rootViewController: vc)
            let aux = UIWindow(windowScene: scene)
            aux.rootViewController = childNav
            aux.windowLevel = .alert
            auxiliaryWindow = aux

            // Bug 1 fix: store the token. The observer handles the external case only —
            // internal dismissal goes through dismissAuxiliaryWindow() which removes the
            // token before hiding, so this block is never reached for those cases.
            let auxID = ObjectIdentifier(aux)
            auxiliaryWindowObserver = NotificationCenter.default.addObserver(
                forName: UIWindow.didBecomeHiddenNotification,
                object: aux,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self,
                          let current = self.auxiliaryWindow,
                          ObjectIdentifier(current) == auxID else { return }
                    if let token = self.auxiliaryWindowObserver {
                        NotificationCenter.default.removeObserver(token)
                        self.auxiliaryWindowObserver = nil
                    }
                    self.auxiliaryWindow = nil
                    self.window?.makeKey()
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
        } else if auxiliaryWindow != nil, isInAuxiliaryHierarchy(active) {
            dismissAuxiliaryWindow()
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

                if !isInAuxiliaryHierarchy(nav), auxiliaryWindow != nil {
                    dismissAuxiliaryWindow()
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
