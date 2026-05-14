import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows {
        window.makeKeyAndOrderFront(self)
      }
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // ── Disable ALL text checking and IME composition marks ──

    // 1. UserDefaults — covers system-level checks
    let defaults = UserDefaults.standard
    let keys = [
      "ContinuousSpellCheckingEnabled",
      "GrammarCheckingEnabled",
      "AutomaticSpellingCorrectionEnabled",
      "NSAutomaticSpellingCorrectionEnabled",
      "NSAutomaticTextCompletionEnabled",
      "WebContinuousSpellCheckingEnabled",
      "NSAutomaticQuoteSubstitutionEnabled",
      "NSAutomaticDashSubstitutionEnabled",
      "NSAutomaticTextReplacementEnabled",
      "NSAutomaticCapitalizationEnabled",
      "NSAutomaticPeriodSubstitutionEnabled",
      "NSAutomaticInlinePredictionEnabled",
    ]
    for key in keys {
      defaults.set(false, forKey: key)
    }

    // 2. Disable the global spell checker
    NSSpellChecker.shared.automaticallyIdentifiesLanguages = false

    // 3. Swizzle NSTextView (base class) — spell check + IME marks
    swizzleSpellCheckingOnClass(NSTextView.self)
    swizzleIMEMarkedText(NSTextView.self)

    // 4. Swizzle FlutterTextInputPlugin — the ACTUAL class Flutter uses.
    //    It's a subclass of NSTextView and may override these properties.
    if let flutterClass = NSClassFromString("FlutterTextInputPlugin") as? NSTextView.Type {
      swizzleSpellCheckingOnClass(flutterClass)
      swizzleIMEMarkedText(flutterClass)
    }
    // Also try alternate class name
    if let flutterClass2 = NSClassFromString("FlutterTextInputSemanticsObject") as? NSView.Type {
      disableSpellCheckOnAnyClass(flutterClass2)
    }

    // 5. Observe new windows and disable on all text views
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidBecomeKey(_:)),
      name: NSWindow.didBecomeKeyNotification,
      object: nil
    )

    super.applicationDidFinishLaunching(notification)
  }

  @objc private func windowDidBecomeKey(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    disableSpellCheckRecursive(window.contentView)
  }

  private func disableSpellCheckRecursive(_ view: NSView?) {
    guard let view = view else { return }
    if let textView = view as? NSTextView {
      textView.isContinuousSpellCheckingEnabled = false
      textView.isGrammarCheckingEnabled = false
      textView.isAutomaticSpellingCorrectionEnabled = false
      textView.isAutomaticQuoteSubstitutionEnabled = false
      textView.isAutomaticDashSubstitutionEnabled = false
      textView.isAutomaticTextReplacementEnabled = false
      textView.isAutomaticTextCompletionEnabled = false
      textView.isAutomaticLinkDetectionEnabled = false
      textView.isAutomaticDataDetectionEnabled = false
    }
    for subview in view.subviews {
      disableSpellCheckRecursive(subview)
    }
  }

  // MARK: - IME Marked Text Swizzling (fixes yellow underlines)

  /// Swizzle IME composition marking methods to strip underline attributes.
  /// The yellow underlines come from macOS IME `setMarkedText:selectedRange:replacementRange:`
  /// adding NSUnderlineStyle attributes, NOT from spell-check.
  private func swizzleIMEMarkedText(_ cls: AnyClass) {
    // 1. Override markedTextAttributes getter to return empty dict
    //    This removes the yellow underline styling entirely
    let markedAttrSel = NSSelectorFromString("markedTextAttributes")
    let emptyDict: @convention(block) (AnyObject) -> [NSAttributedString.Key: Any]? = { _ in
      return [:]
    }
    let emptyDictImp = imp_implementationWithBlock(emptyDict)
    if let method = class_getInstanceMethod(cls, markedAttrSel) {
      method_setImplementation(method, emptyDictImp)
    } else {
      class_addMethod(cls, markedAttrSel, emptyDictImp, "@16@0:8")
    }

    // 2. Override markedTextAttributes setter to no-op
    let setMarkedAttrSel = NSSelectorFromString("setMarkedTextAttributes:")
    let noopSetDict: @convention(block) (AnyObject, Any?) -> Void = { _, _ in }
    let noopSetDictImp = imp_implementationWithBlock(noopSetDict)
    if let method = class_getInstanceMethod(cls, setMarkedAttrSel) {
      method_setImplementation(method, noopSetDictImp)
    } else {
      class_addMethod(cls, setMarkedAttrSel, noopSetDictImp, "v24@0:8@16")
    }

    // 3. Override validAttributesForMarkedText to return empty array
    //    This tells the system no attributes are valid for marked text
    let validAttrSel = NSSelectorFromString("validAttributesForMarkedText")
    let emptyArray: @convention(block) (AnyObject) -> [Any] = { _ in [] }
    let emptyArrayImp = imp_implementationWithBlock(emptyArray)
    if let method = class_getInstanceMethod(cls, validAttrSel) {
      method_setImplementation(method, emptyArrayImp)
    } else {
      class_addMethod(cls, validAttrSel, emptyArrayImp, "@16@0:8")
    }
  }

  // MARK: - Spell Check Swizzling

  /// Swizzle all spell-check getter/setter methods on an NSTextView-compatible class.
  private func swizzleSpellCheckingOnClass(_ cls: AnyClass) {
    // Getter selectors — all return Bool
    let getterSelectors: [Selector] = [
      #selector(getter: NSTextView.isContinuousSpellCheckingEnabled),
      #selector(getter: NSTextView.isGrammarCheckingEnabled),
      #selector(getter: NSTextView.isAutomaticSpellingCorrectionEnabled),
      #selector(getter: NSTextView.isAutomaticQuoteSubstitutionEnabled),
      #selector(getter: NSTextView.isAutomaticDashSubstitutionEnabled),
      #selector(getter: NSTextView.isAutomaticTextReplacementEnabled),
      #selector(getter: NSTextView.isAutomaticTextCompletionEnabled),
    ]

    let alwaysFalse: @convention(block) (AnyObject) -> Bool = { _ in false }
    let falseImp = imp_implementationWithBlock(alwaysFalse)

    for sel in getterSelectors {
      if let method = class_getInstanceMethod(cls, sel) {
        method_setImplementation(method, falseImp)
      } else {
        let typeEncoding = "B@:" // BOOL, self, _cmd
        class_addMethod(cls, sel, falseImp, typeEncoding)
      }
    }

    // Setter selectors — no-op so nothing can re-enable
    let setterSelectors: [Selector] = [
      #selector(setter: NSTextView.isContinuousSpellCheckingEnabled),
      #selector(setter: NSTextView.isGrammarCheckingEnabled),
      #selector(setter: NSTextView.isAutomaticSpellingCorrectionEnabled),
      #selector(setter: NSTextView.isAutomaticQuoteSubstitutionEnabled),
      #selector(setter: NSTextView.isAutomaticDashSubstitutionEnabled),
      #selector(setter: NSTextView.isAutomaticTextReplacementEnabled),
      #selector(setter: NSTextView.isAutomaticTextCompletionEnabled),
    ]

    let noopSetter: @convention(block) (AnyObject, Bool) -> Void = { _, _ in }
    let noopImp = imp_implementationWithBlock(noopSetter)

    for sel in setterSelectors {
      if let method = class_getInstanceMethod(cls, sel) {
        method_setImplementation(method, noopImp)
      } else {
        let typeEncoding = "v@:B" // void, self, _cmd, BOOL
        class_addMethod(cls, sel, noopImp, typeEncoding)
      }
    }

    // Also swizzle the important check methods
    let checkSel = NSSelectorFromString("checkTextInRange:types:options:")
    let noopCheck: @convention(block) (AnyObject, NSRange, UInt64, [String: Any]) -> Void = { _, _, _, _ in }
    let noopCheckImp = imp_implementationWithBlock(noopCheck)
    if let method = class_getInstanceMethod(cls, checkSel) {
      method_setImplementation(method, noopCheckImp)
    }

    let handleSel = NSSelectorFromString("handleTextCheckingResults:forRange:types:options:orthography:wordCount:")
    let noopHandle: @convention(block) (AnyObject, [Any], NSRange, UInt64, [String: Any], Any?, Int) -> Void = { _, _, _, _, _, _, _ in }
    let noopHandleImp = imp_implementationWithBlock(noopHandle)
    if let method = class_getInstanceMethod(cls, handleSel) {
      method_setImplementation(method, noopHandleImp)
    }
  }

  /// For non-NSTextView classes, try disabling via known selectors
  private func disableSpellCheckOnAnyClass(_ cls: AnyClass) {
    let checkSel = NSSelectorFromString("checkTextInRange:types:options:")
    let noopCheck: @convention(block) (AnyObject, NSRange, UInt64, [String: Any]) -> Void = { _, _, _, _ in }
    let noopCheckImp = imp_implementationWithBlock(noopCheck)
    if let method = class_getInstanceMethod(cls, checkSel) {
      method_setImplementation(method, noopCheckImp)
    }
  }
}
