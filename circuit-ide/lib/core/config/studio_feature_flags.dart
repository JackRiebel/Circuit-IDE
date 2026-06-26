class StudioFeatureFlags {
  const StudioFeatureFlags._();

  // Enterprise specialists stay hidden until they are fully backed by the
  // request-local Studio turn runtime, permissions, context, and tests.
  static const enterpriseSpecialists = false;

  // Broad experimental surfaces stay out of the main Studio shell until they
  // obey the same intent, context, permission, and turn outcome contracts.
  static const advancedStudioSurfaces = false;
}
