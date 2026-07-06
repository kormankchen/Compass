@MainActor
public enum NavigationEvent {
    case shouldDismiss(@MainActor () -> Bool)
    case didDismiss(@MainActor () -> Void)
}
