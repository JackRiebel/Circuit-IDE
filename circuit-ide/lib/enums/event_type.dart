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

  // Checkpoint events
  checkpointCreated,
  checkpointReverted,

  // MCP events
  mcpServerConnecting,
  mcpServerConnected,
  mcpServerDisconnected,
  mcpServerError,
  mcpToolCallStarted,
  mcpToolCallCompleted,
  mcpToolsUpdated,
}
