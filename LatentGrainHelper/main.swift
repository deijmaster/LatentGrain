import Foundation

// MARK: - LatentGrainHelper entry point
//
// This binary is installed as an XPC Service (Phase 1) or SMAppService
// privileged helper (Phase 2). It listens for connections from the main
// LatentGrain.app and responds to LatentGrainXPCProtocol requests.

let delegate = HelperDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()

// Block the main thread — the XPC runtime drives everything via the listener.
RunLoop.main.run()
