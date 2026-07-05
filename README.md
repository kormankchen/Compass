<p align="center">
  <img src="assets/logo.svg" width="120" alt="Compass">
</p>

<h1 align="center">Compass</h1>

<p align="center">
  A Swift navigation framework for iOS that wraps UIKit navigation behind a clean, UIKit-free API.<br>
  Built with Swift 6, <code>@MainActor</code> isolation, and a traversal-based architecture that reads UIKit state directly.
</p>

---

## Requirements

- iOS 16+
- Swift 6

## Installation

```swift
// Package.swift
.package(url: "https://github.com/kormankchen/Compass", from: "1.0.0")
```

## Setup

```swift
// SceneDelegate.swift
func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }
    Compass.configure(root: HomeScreen(), modules: [
        AuthModule.self,
        ProfileModule.self,
    ], in: windowScene)
}
```

Compass creates and owns the `UIWindow`. No window setup needed in your SceneDelegate.

## Screens

Screens are pure data models — no UIKit, no factory methods.

```swift
struct HomeScreen: Screen {}
struct ProfileScreen: Screen { let userID: String }
struct LoginScreen: Screen {}
```

## Modules

Modules register factory closures for each screen. UIKit (or SwiftUI) lives here.

```swift
struct ProfileModule: NavigatorModule {
    static func register(in registry: any ScreenRegistry) {
        // UIKit
        registry.register(ProfileScreen.self) { screen in
            ProfileViewController(userID: screen.userID)
        }
        // SwiftUI
        registry.register(HomeScreen.self) { _ in
            HomeView()
        }
    }
}
```

## Navigation

```swift
// Push
Compass.shared.route(to: ProfileScreen(userID: "42"), via: .push)

// Modal
Compass.shared.route(to: LoginScreen(), via: .sheet)
Compass.shared.route(to: LoginScreen(), via: .fullScreen)
Compass.shared.route(to: LoginScreen(), via: .overFullScreen)

// New window (floats above all content)
Compass.shared.route(to: AlertScreen(), via: .newWindow)

// Dismiss top
Compass.shared.dismiss()

// Dismiss to first occurrence of a screen type
try Compass.shared.dismiss(to: ProfileScreen.self)

// Dismiss to a specific instance
try Compass.shared.dismiss(to: ProfileScreen.self, matching: { $0.userID == "42" })
```

`dismiss(to:)` traverses the entire UIKit hierarchy — across push stacks and modal levels — and unwinds everything above the target in a single call.

## Transitions

| Transition | Behaviour |
|---|---|
| `.push` | Push onto the current navigation stack |
| `.sheet` | Modal with `.pageSheet` style |
| `.fullScreen` | Modal with `.fullScreen` style |
| `.overFullScreen` | Modal with `.overFullScreen` style |
| `.newWindow` | New `UIWindow` floating above all navigation |

## Dependency Injection / Testing

Depend on `any Navigator` in your view models and inject `Compass.shared` at the call site. For tests, add `CompassTestSupport` to your test target and use the provided mocks.

```swift
class ProfileViewModel {
    private let navigator: any Navigator
    init(navigator: any Navigator = Compass.shared) { self.navigator = navigator }
    func openLogin() { navigator.route(to: LoginScreen(), via: .sheet) }
}
```

```swift
// Package.swift test target
.testTarget(name: "AppTests", dependencies: [
    "App",
    .product(name: "CompassTestSupport", package: "Compass"),
])
```

```swift
// Tests
import CompassTestSupport

@Test func opensLoginOnTap() {
    let nav = MockNavigator()
    let vm = ProfileViewModel(navigator: nav)
    vm.openLogin()
    #expect(nav.routeCalls.last?.screen == AnyHashable(LoginScreen()))
    #expect(nav.routeCalls.last?.transition == .sheet)
}

@Test func moduleRegistersExpectedScreens() {
    let registry = MockScreenRegistry()
    ProfileModule.register(in: registry)
    #expect(registry.hasRegistered(ProfileScreen.self))
}
```

## External Navigation

Compass reads UIKit's `viewControllers` and `presentedViewController` chain directly, so navigation that happens outside the framework (system back button, swipe-to-pop, external `dismiss()` calls) is automatically reflected.

**Known limitation:** SwiftUI `NavigationStack` routes are below the UIKit layer and cannot be tracked.
