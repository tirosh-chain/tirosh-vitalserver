import Foundation
import UpdateLayerEffectExecutor

@main
struct GuestRuntimeLayerEffectExecutorMain {
    static func main() async {
        await runLayerEffectExecutor(.guestRuntime)
    }
}
