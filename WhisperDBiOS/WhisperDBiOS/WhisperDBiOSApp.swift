import SwiftUI

@main
struct WhisperDBiOSApp: App {
    @StateObject private var viewModel = RecordingViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onOpenURL { url in
                    if url.host == "stop" {
                        viewModel.stopIfRecording()
                    }
                }
        }
    }
}
