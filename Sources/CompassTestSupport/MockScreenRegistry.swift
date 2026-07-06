import UIKit
import Compass

public final class MockScreenRegistry: ScreenRegistry {
    public private(set) var registeredTypeIDs: [ObjectIdentifier] = []

    public init() {}

    public func register<S: Screen>(_ type: S.Type, factory: @escaping @MainActor (ScreenContext<S>) -> UIViewController) {
        registeredTypeIDs.append(ObjectIdentifier(type))
    }

    public func hasRegistered<S: Screen>(_ type: S.Type) -> Bool {
        registeredTypeIDs.contains(ObjectIdentifier(type))
    }
}
