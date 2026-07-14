class StudioFeatureFlags {
  const StudioFeatureFlags._();

  // Enterprise specialists stay hidden until they are fully backed by the
  // request-local Studio turn runtime, permissions, context, and tests.
  static const enterpriseSpecialists = false;

  // Broad experimental surfaces stay out of the main Studio shell until they
  // obey the same intent, context, permission, and turn outcome contracts.
  static const advancedStudioSurfaces = false;

  // User-controlled preview is deliberately narrower than the broad advanced
  // surface gate: it never grants an agent browser/computer control and only
  // shares a user-selected observation with a task through an explicit action.
  static const browserPreview = true;

  // Computer use has no enabled executor. Its future isolated-session policy
  // is tested separately, but no Studio turn may request desktop control.
  static const computerUse = false;
}
