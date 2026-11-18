import SwiftUI

@main
struct CurrencyConverterApp: App {
    @State private var model = ConverterViewModel(repository: .live())
    private let history = RateHistoryRepository(api: ServerRatesAPI.live())
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // Unit tests run inside the app as their host; without this the host would
            // start loading rates from the server during every test run.
            if Self.isHostingUnitTests {
                Color.clear
            } else {
                ConverterView(model: model, history: history)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from the background: revalidate only if the cached rates have expired.
            if phase == .active, !Self.isHostingUnitTests {
                Task { await model.refreshIfNeeded() }
            }
        }
    }

    private static let isHostingUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
