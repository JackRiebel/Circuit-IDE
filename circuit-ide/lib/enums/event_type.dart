enum EventType {
  // Connection events
  connecting,
  connected,
  disconnected,
  connectionError,

  // Chat events
  messageStarted,
  messageChunk,
  messageCompleted,
  messageError,

  // Tool events
  toolCallStarted,
  toolCallCompleted,
  toolCallError,
  toolResultRecorded,

  // Confirmation events
  confirmationNeeded,
  confirmationReceived,
  confirmationTimeout,

  // Status events
  statusChanged,
  tokensUpdated,
  costUpdated,
  modelChanged,

  // Session events
  sessionSaved,
  sessionLoaded,
  historyCleared,

  // Agent state
  thinkingStarted,
  thinkingCompleted,
  agentRunEvent,
  providerLifecycle,

  // Checkpoint events
  checkpointCreated,
  checkpointReverted,

  // Orchestration events
  orchestrationStarted,
  orchestrationCompleted,
  orchestrationFailed,

  // MCP events
  mcpServerConnecting,
  mcpServerConnected,
  mcpServerDisconnected,
  mcpServerError,
  mcpToolCallStarted,
  mcpToolCallCompleted,
  mcpToolsUpdated,

  // Vericoding events
  vericodeTriggered,
  vericodePassed,
  vericodeFailed,

  // Ghost mode events
  ghostStarted,
  ghostCompleted,
  ghostFailed,
  ghostUndone,

  // Runtime visualization events
  runtimeAnalyzing,
  runtimeReady,
}
