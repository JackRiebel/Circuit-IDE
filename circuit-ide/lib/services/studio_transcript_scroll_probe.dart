/// In-process hook used only by the private packaged performance probe.
///
/// It has no platform channel, user-facing control, or agent/tool route. A
/// transcript registers its existing scroll controller only while the probe
/// has explicitly started, then unregisters when it unmounts. This lets the
/// packaged Release harness measure real ListView frame timings without
/// introducing a diagnostic surface into the product.
typedef StudioTranscriptScrollProbeDriver =
    Future<bool> Function({required int stepCount});
typedef StudioTranscriptScrollProbePreparation = Future<bool> Function();

class StudioTranscriptScrollProbe {
  static bool _enabled = false;
  static Object? _owner;
  static StudioTranscriptScrollProbePreparation? _preparer;
  static StudioTranscriptScrollProbeDriver? _driver;

  static bool get isReady => _enabled && _preparer != null && _driver != null;

  static void beginPackagedProbe() {
    _enabled = true;
    _owner = null;
    _preparer = null;
    _driver = null;
  }

  static void endPackagedProbe() {
    _enabled = false;
    _owner = null;
    _preparer = null;
    _driver = null;
  }

  static void register({
    required Object owner,
    required StudioTranscriptScrollProbePreparation prepare,
    required StudioTranscriptScrollProbeDriver driver,
  }) {
    if (!_enabled) return;
    _owner = owner;
    _preparer = prepare;
    _driver = driver;
  }

  static void unregister(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _preparer = null;
    _driver = null;
  }

  /// Moves the real transcript into a known starting position before the
  /// timing window begins. Keeping this distinct from [drive] prevents the
  /// setup jump from being reported as a user scroll frame.
  static Future<bool> prepare() async {
    if (!_enabled) return false;
    final preparer = _preparer;
    if (preparer == null) return false;
    return preparer();
  }

  static Future<bool> drive({int stepCount = 8}) async {
    if (!_enabled || stepCount < 1) return false;
    final driver = _driver;
    if (driver == null) return false;
    return driver(stepCount: stepCount);
  }
}
