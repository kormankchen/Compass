import UIKit

public enum Transition: Sendable {
    case push
    case sheet
    case fullScreen
    case overFullScreen
    case newWindow
}

extension Transition {
    var uiKitStyle: UIModalPresentationStyle {
        switch self {
        case .sheet:          return .pageSheet
        case .fullScreen:     return .fullScreen
        case .overFullScreen: return .overFullScreen
        case .push, .newWindow:
            preconditionFailure("Transition.\(self) has no UIModalPresentationStyle")
        }
    }
}
