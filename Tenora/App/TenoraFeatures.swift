enum TenoraFeatures {
    #if TENORA_AGENT_BRIDGE_ENABLED
    static let agentBridgeEnabled = true
    #else
    static let agentBridgeEnabled = false
    #endif
}
