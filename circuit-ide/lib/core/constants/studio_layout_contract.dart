/// The desktop Studio geometry contract. These are upper bounds and fixed
/// chrome dimensions; Flutter still constrains every surface to the available
/// window so the layout can shrink safely between the supported viewports.
abstract final class StudioLayoutContract {
  static const minimumDesktopWidth = 1366.0;
  static const minimumDesktopHeight = 768.0;
  static const comfortableDesktopWidth = 1440.0;
  static const comfortableDesktopHeight = 900.0;

  static const leftRailWidth = 236.0;
  static const topBarHeight = 43.0;
  static const transcriptHorizontalInset = 40.0;
  // Keep roughly two viewports of nearby transcript rows laid out. This avoids
  // a large build burst when users scroll quickly through long conversations
  // without turning the transcript into an eagerly-built history.
  static const transcriptCacheExtent = 1600.0;

  static const collapsedDrawerWidth = 52.0;
  static const standardDrawerWidth = 300.0;
  static const expandedDrawerWidth = 508.0;
  static const splitDrawerWidth = 668.0;

  static const proseWidth = 760.0;
  static const composerWidth = 840.0;
  static const artifactWidth = 960.0;
  static const reviewWidth = 1040.0;

  static const projectDialogWidth = 420.0;
  static const checkpointDialogWidth = 430.0;
  static const taskDecisionDialogWidth = 680.0;
}
