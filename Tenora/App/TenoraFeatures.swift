enum TenoraFeatures {
    #if TENORA_AGENT_BRIDGE_ENABLED
    static let agentBridgeEnabled = true
    #else
    static let agentBridgeEnabled = false
    #endif

    /// Emergency gates remain off until reconciliation and multi-device tests pass.
    static let personalSyncReadEnabled = false
    static let personalSyncWriteEnabled = false
}
