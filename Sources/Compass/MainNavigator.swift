import UIKit

// MARK: - CompassNavigationController

// UINavigationController already conforms to UINavigationBarDelegate and sets itself as
// navigationBar.delegate, so declaring the method here (without override) provides our
// implementation as the delegate — no separate delegate assignment needed.
@MainActor
final class CompassNavigationController: UINavigationController, UINavigationBarDelegate {
    weak var compassNavigator: MainNavigator?

    func navigationBar(_ navigationBar: UINavigationBar, shouldPop item: UINavigationItem) -> Bool {
        if let vc = viewControllers.first(where: { $0.navigationItem === item }),
           let ctx = compassNavigator?.vcContextMap[ObjectIdentifier(vc)] {
            return ctx.evaluateShouldDismiss()
        }
        return true
    }
}

// MARK: - MainNavigator

@MainActor
final class MainNavigator: Navigator {

    static var instance: MainNavigator?

    let navController: CompassNavigationController
    var window: UIWindow?
    private var auxiliaryWindow: UIWindow?
    private var auxiliaryWindowObserver: NSObjectProtocol?
    private let registry: MainRegistry
    private let navDelegate: NavigatorDelegate
    var vcScreenMap: [ObjectIdentifier: AnyHashable] = [:]
    var vcContextMap: [ObjectIdentifier: any AnyScreenContext] = [:]

    init<S: Screen>(root: S, registry: MainRegistry) {
        let context = ScreenContext(root)
        guard let rootVC = registry.makeViewController(for: context) else {
            fatalError("No factory registered for \(type(of: root)). Register it in a NavigatorModule.")
        }
        self.registry = registry
        let nav = CompassNavigationController(rootViewController: rootVC)
        navController = nav
        let del = NavigatorDelegate()
        navDelegate = del
        del.owner = self
        nav.delegate = del
        nav.compassNavigator = self
        vcScreenMap[ObjectIdentifier(rootVC)] = AnyHashable(root)
        vcContextMap[ObjectIdentifier(rootVC)] = context
    }

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

    private func dismissAuxiliaryWindow() {
        if let token = auxiliaryWindowObserver {
            NotificationCenter.default.removeObserver(token)
            auxiliaryWindowObserver = nil
        }
        if let aux = auxiliaryWindow {
            let auxVCs = (aux.rootViewController as? UINavigationController)?.viewControllers
                ?? [aux.rootViewController].compactMap { $0 }
            auxVCs.forEach { vcContextMap[ObjectIdentifier($0)]?.notifyDidDismiss() }
        }
        auxiliaryWindow?.isHidden = true
        auxiliaryWindow = nil
        window?.makeKey()
        let liveIDs = Set(collectAllVCs().map { ObjectIdentifier($0) })
        vcScreenMap = vcScreenMap.filter { liveIDs.contains($0.key) }
        vcContextMap = vcContextMap.filter { liveIDs.contains($0.key) }
    }

    // MARK: - Navigator

    func route<S: Screen>(to context: ScreenContext<S>, via transition: Transition, animated: Bool) {
        guard let vc = registry.makeViewController(for: context) else {
            fatalError("No factory registered for \(type(of: context.screen)). Register it in a NavigatorModule.")
        }
        vcScreenMap[ObjectIdentifier(vc)] = AnyHashable(context.screen)
        vcContextMap[ObjectIdentifier(vc)] = context

        switch transition {
        case .push:
            activeNavController.pushViewController(vc, animated: animated)

        case .sheet, .fullScreen, .overFullScreen:
            let childNav = UINavigationController(rootViewController: vc)
            childNav.modalPresentationStyle = transition.uiKitStyle
            activeNavController.present(childNav, animated: animated)
            childNav.presentationController?.delegate = navDelegate

        case .newWindow:
            guard let scene = window?.windowScene else {
                assertionFailure("Compass: no UIWindowScene available for newWindow transition")
                return
            }
            if auxiliaryWindow != nil { dismissAuxiliaryWindow() }

            let childNav = UINavigationController(rootViewController: vc)
            let aux = UIWindow(windowScene: scene)
            aux.rootViewController = childNav
            aux.windowLevel = .alert
            auxiliaryWindow = aux

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
                    let auxVCs = (current.rootViewController as? UINavigationController)?.viewControllers
                        ?? [current.rootViewController].compactMap { $0 }
                    auxVCs.forEach { self.vcContextMap[ObjectIdentifier($0)]?.notifyDidDismiss() }
                    self.auxiliaryWindow = nil
                    self.window?.makeKey()
                    let liveIDs = Set(self.collectAllVCs().map { ObjectIdentifier($0) })
                    self.vcScreenMap = self.vcScreenMap.filter { liveIDs.contains($0.key) }
                    self.vcContextMap = self.vcContextMap.filter { liveIDs.contains($0.key) }
                }
            }
            aux.makeKeyAndVisible()
        }
    }

    func dismiss(animated: Bool, completion: (() -> Void)?) {
        let active = activeNavController
        if active.viewControllers.count > 1 {
            CATransaction.begin()
            CATransaction.setCompletionBlock(completion)
            active.popViewController(animated: animated)
            CATransaction.commit()
        } else if auxiliaryWindow != nil, isInAuxiliaryHierarchy(active) {
            dismissAuxiliaryWindow()
            completion?()
        } else if active !== navController {
            active.dismiss(animated: animated, completion: completion)
        } else {
            completion?()
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
final class NavigatorDelegate: NSObject, UIAdaptivePresentationControllerDelegate, UINavigationControllerDelegate {
    weak var owner: MainNavigator?
    private var previousTopVC: UIViewController?

    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        guard let owner else { return true }
        let presented = presentationController.presentedViewController
        let rootVC = (presented as? UINavigationController)?.viewControllers.first ?? presented
        return owner.vcContextMap[ObjectIdentifier(rootVC)]?.evaluateShouldDismiss() ?? true
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let owner else { return }
        let presented = presentationController.presentedViewController
        let rootVC = (presented as? UINavigationController)?.viewControllers.first ?? presented
        owner.vcContextMap[ObjectIdentifier(rootVC)]?.notifyDidDismiss()
        let liveIDs = Set(owner.collectAllVCs().map { ObjectIdentifier($0) })
        owner.vcScreenMap = owner.vcScreenMap.filter { liveIDs.contains($0.key) }
        owner.vcContextMap = owner.vcContextMap.filter { liveIDs.contains($0.key) }
    }

    func navigationController(_ navigationController: UINavigationController,
                               willShow viewController: UIViewController, animated: Bool) {
        previousTopVC = navigationController.viewControllers.last
    }

    func navigationController(_ navigationController: UINavigationController,
                               didShow viewController: UIViewController, animated: Bool) {
        if let popped = previousTopVC, !navigationController.viewControllers.contains(popped) {
            let id = ObjectIdentifier(popped)
            owner?.vcContextMap[id]?.notifyDidDismiss()
            owner?.vcContextMap.removeValue(forKey: id)
            owner?.vcScreenMap.removeValue(forKey: id)
        }
        previousTopVC = nil
    }
}
