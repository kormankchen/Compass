import Testing
import UIKit
import Compass
import CompassTestSupport

@MainActor
struct MockNavigatorTests {
    @Test func routeRecordsCall() {
        let nav = MockNavigator()
        let screen = TestScreen(id: "1")
        nav.route(to: screen, via: .push)
        #expect(nav.routeCalls.count == 1)
        #expect(nav.routeCalls.first?.screen == AnyHashable(screen))
        #expect(nav.routeCalls.first?.transition == .push)
    }

    @Test func dismissIncrementsCount() {
        let nav = MockNavigator()
        nav.dismiss()
        nav.dismiss()
        #expect(nav.dismissCount == 2)
    }

    @Test func dismissToRecordsType() throws {
        let nav = MockNavigator()
        try nav.dismiss(to: TestScreen.self)
        #expect(nav.lastDismissType == TestScreen.self)
    }
}

@MainActor
struct MockScreenRegistryTests {
    @Test func registersScreenType() {
        let registry = MockScreenRegistry()
        registry.register(TestScreen.self) { _ in UIViewController() }
        #expect(registry.hasRegistered(TestScreen.self))
    }

    @Test func doesNotReportUnregisteredType() {
        let registry = MockScreenRegistry()
        #expect(!registry.hasRegistered(TestScreen.self))
    }
}

private struct TestScreen: Screen {
    let id: String
}
