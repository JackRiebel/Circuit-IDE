import 'package:flutter/material.dart';

/// Resolves decorative Studio motion against the platform accessibility setting.
///
/// A zero duration preserves the final visual state without a transition when
/// macOS asks applications to reduce motion.
Duration studioMotionDuration(BuildContext context, Duration duration) {
  return (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
      ? Duration.zero
      : duration;
}
