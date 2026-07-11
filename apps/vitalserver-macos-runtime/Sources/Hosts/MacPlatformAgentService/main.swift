import MacPlatformAgent

@main
@MainActor
struct MacPlatformAgentServiceMain {
    static func main() throws {
        try MacPlatformAgentService.live().run()
    }
}
