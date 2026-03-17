import Combine
import Foundation

@MainActor
public final class WindowSceneState: ObservableObject {
    @Published public var showingAddPaneSheet: Bool

    public init(showingAddPaneSheet: Bool = false) {
        self.showingAddPaneSheet = showingAddPaneSheet
    }
}
