import SwiftUI

@main
struct CurrencyConverterApp: App {
    @State private var model = ConverterViewModel(repository: .live)

    var body: some Scene {
        WindowGroup {
            ConverterView(model: model)
        }
    }
}
