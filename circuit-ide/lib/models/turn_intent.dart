import 'studio_shell.dart';

enum TurnIntent { chat, ask, plan, code, review, verify }

enum IntentContractKind {
  conversational,
  readOnly,
  planning,
  coding,
  reviewing,
  verifying,
}

class IntentContract {
  final TurnIntent intent;
  final IntentContractKind kind;
  final bool mayCreateWorkspace;
  final bool mayExposeTools;
  final bool mayInspectWorkspace;
  final bool mayProposePatch;
  final bool mayApplyPatch;
  final bool mayRunCommands;

  const IntentContract({
    required this.intent,
    required this.kind,
    required this.mayCreateWorkspace,
    required this.mayExposeTools,
    required this.mayInspectWorkspace,
    required this.mayProposePatch,
    required this.mayApplyPatch,
    required this.mayRunCommands,
  });

  static IntentContract forIntent(TurnIntent intent) {
    return switch (intent) {
      TurnIntent.chat => const IntentContract(
        intent: TurnIntent.chat,
        kind: IntentContractKind.conversational,
        mayCreateWorkspace: false,
        mayExposeTools: false,
        mayInspectWorkspace: false,
        mayProposePatch: false,
        mayApplyPatch: false,
        mayRunCommands: false,
      ),
      TurnIntent.ask => const IntentContract(
        intent: TurnIntent.ask,
        kind: IntentContractKind.readOnly,
        mayCreateWorkspace: false,
        mayExposeTools: true,
        mayInspectWorkspace: true,
        mayProposePatch: false,
        mayApplyPatch: false,
        mayRunCommands: false,
      ),
      TurnIntent.plan => const IntentContract(
        intent: TurnIntent.plan,
        kind: IntentContractKind.planning,
        mayCreateWorkspace: true,
        mayExposeTools: true,
        mayInspectWorkspace: true,
        mayProposePatch: true,
        mayApplyPatch: false,
        mayRunCommands: false,
      ),
      TurnIntent.code => const IntentContract(
        intent: TurnIntent.code,
        kind: IntentContractKind.coding,
        mayCreateWorkspace: true,
        mayExposeTools: true,
        mayInspectWorkspace: true,
        mayProposePatch: true,
        mayApplyPatch: false,
        mayRunCommands: false,
      ),
      TurnIntent.review => const IntentContract(
        intent: TurnIntent.review,
        kind: IntentContractKind.reviewing,
        mayCreateWorkspace: false,
        mayExposeTools: true,
        mayInspectWorkspace: true,
        mayProposePatch: false,
        mayApplyPatch: false,
        mayRunCommands: false,
      ),
      TurnIntent.verify => const IntentContract(
        intent: TurnIntent.verify,
        kind: IntentContractKind.verifying,
        mayCreateWorkspace: false,
        mayExposeTools: true,
        mayInspectWorkspace: true,
        mayProposePatch: false,
        mayApplyPatch: false,
        mayRunCommands: true,
      ),
    };
  }
}

class IntentClassifier {
  const IntentClassifier._();

  static TurnIntent classify(
    String prompt, {
    required StudioPromptMode promptMode,
    required bool planModeEnabled,
  }) {
    final normalized = _normalize(prompt);
    if (normalized.isEmpty) return TurnIntent.chat;
    if (_isConversational(normalized)) return TurnIntent.chat;
    if (_looksLikeProductInceptionRequest(normalized)) return TurnIntent.ask;
    if (planModeEnabled) return TurnIntent.plan;
    if (_looksLikePlanRequest(normalized)) return TurnIntent.plan;
    if (_looksLikeSourceFileOutputRequest(normalized)) return TurnIntent.code;
    if (_looksLikeDocumentArtifactFileOutputRequest(normalized)) {
      return TurnIntent.plan;
    }
    if (_looksLikeDesignArtifactRequest(normalized)) return TurnIntent.plan;
    if (_looksLikeReviewRequest(normalized)) return TurnIntent.review;
    if (_looksLikeAdvisoryQuestion(normalized)) return TurnIntent.ask;
    if (_looksLikeReadOnlyQuestion(normalized)) return TurnIntent.ask;
    if (_requestsChatOnlyOutput(normalized)) return TurnIntent.ask;
    if (_looksLikeKnowledgeArtifactRequest(normalized)) return TurnIntent.ask;
    if (_looksLikeEnterpriseAdvisoryRequest(normalized)) return TurnIntent.ask;
    if (_looksLikeImplementationWithVerification(normalized)) {
      return TurnIntent.code;
    }
    if (_looksLikeOperationalCommand(normalized)) return TurnIntent.verify;
    if (_looksLikeVerification(normalized)) return TurnIntent.verify;
    return switch (promptMode) {
      StudioPromptMode.ask => TurnIntent.ask,
      StudioPromptMode.code => TurnIntent.code,
      StudioPromptMode.fix => TurnIntent.code,
      StudioPromptMode.review => TurnIntent.review,
    };
  }

  static bool isConversational(String prompt) {
    return _isConversational(_normalize(prompt));
  }

  static bool requestsVerification(String prompt) {
    return _looksLikeVerification(_normalize(prompt));
  }

  static bool requestsStructuredAdvisoryOutput(String prompt) {
    final normalized = _normalize(prompt);
    if (normalized.isEmpty) return false;
    if (_hasExplicitFileOutputRequest(normalized)) return false;
    return _looksLikeDesignOrVisualArtifact(normalized) ||
        _looksLikeKnowledgeArtifactRequest(normalized) ||
        _looksLikeEnterpriseAdvisoryRequest(normalized);
  }

  static bool requestsBuildDiscovery(String prompt) {
    return _looksLikeProductInceptionRequest(_normalize(prompt));
  }

  static String _normalize(String prompt) {
    return prompt
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s!?]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool _isConversational(String normalized) {
    const exact = {
      'hi',
      'hello',
      'hey',
      'yo',
      'howdy',
      'good morning',
      'good afternoon',
      'good evening',
      'thanks',
      'thank you',
      'yes',
      'yeah',
      'yep',
      'yup',
      'sure',
      'ok',
      'okay',
      'cool',
      'nice',
      'great',
      'perfect',
      'sounds good',
      'got it',
      'all good',
      'approve',
      'approved',
      'approve it',
      'accept',
      'accepted',
      'accept it',
      'looks good',
      'looks good to me',
      'go ahead',
      'proceed',
      'continue',
      'continue please',
      'start',
      'begin',
      'do it',
      'do that',
      'ship it',
      'implement it',
      'implement this',
      'apply it',
      'apply this',
      'apply the plan',
      'apply this plan',
      'can you do that',
      'could you do that',
      'would you do that',
      'please do that',
      'make that happen',
      'can you make that happen',
      'could you make that happen',
      'yes please',
      'yes please do that',
      'sounds good do that',
      'that works do that',
      'let s do it',
      'next',
      'next step',
      'what can you do',
      'help',
      'help me',
      'can you help',
      'can you help me',
      'could you help',
      'could you help me',
    };
    if (exact.contains(normalized)) return true;
    if (RegExp(
      r'^(hi|hello|hey|yo|howdy)[!\s]*(circuit|there)?[!\s]*$',
    ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(
      r'^(thanks|thank you|thx)[!\s]*(circuit)?[!\s]*$',
    ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(
      r'^(yes|yeah|yep|yup|sure|ok|okay|cool|great|perfect|continue|go ahead|proceed|start|begin|do it|ship it|approve|approved|accept|accepted)[!\s]*(please)?[!\s]*$',
    ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(
      r'^(please\s+)?(approve|approved|accept|accepted)(\s+(it|this|that|the plan|this plan|as described))?[!\s]*$',
    ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(
      r'^(yes|yeah|yep|yup|sure|ok|okay)\s+(please\s+)?(implement|apply|start|proceed|continue|do it|ship it)(\s+(it|this|that|the plan|this plan))?[!\s]*$',
    ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(
      r'^(yes|yeah|yep|yup|sure|ok|okay|sounds\s+good|that\s+works|looks\s+good)(\s+please)?\s+(do|apply|implement|continue|proceed|start|begin|ship|make)\s+(it|this|that|the\s+plan|this\s+plan|the\s+changes|those\s+changes|these\s+changes|same\s+thing)(\s+happen)?[!\s]*$',
    ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(
      r'^(can|could|would|will)\s+you\s+(please\s+)?(do|apply|implement|continue|proceed|start|begin|ship|make)\s+(it|this|that|the\s+plan|this\s+plan|the\s+changes|those\s+changes|these\s+changes|what\s+you\s+suggested|what\s+you\s+recommended)(\s+happen)?(\s+please)?[!\s?]*$',
    ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(
      r'^(please\s+)?(do|make|apply|implement)\s+(it|this|that|the\s+same\s+thing|same\s+thing)(\s+happen)?[!\s]*$',
    ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(
      r'^(let\s+s|lets)\s+(do|ship|apply|implement)\s+(it|this|that|the\s+plan)?[!\s]*$',
    ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(r'^(the\s+)?next\s+step[!\s?]*$').hasMatch(normalized)) {
      return true;
    }
    if (RegExp(
      r'^(please\s+)?(proceed|continue|go ahead|start|begin|do it|ship it|implement it|implement this|apply it|apply this|apply the plan|apply this plan)(\s+(with|on)\s+(it|this|that|the plan|this plan|the implementation|the changes))?[!\s]*$',
    ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(
      r'^(please\s+)?(continue|proceed|go ahead|start|begin|do|apply|implement|make)\s+((with|on|from)\s+)?(where\s+you\s+left\s+off|the\s+next\s+step|next\s+step|the\s+changes|those\s+changes|these\s+changes|the\s+edits|those\s+edits|the\s+patch|that\s+patch|the\s+plan|that\s+plan|what\s+you\s+suggested|what\s+you\s+recommended|your\s+suggestion|your\s+recommendation|the\s+same\s+thing|same\s+as\s+above)(\s+(you\s+suggested|you\s+recommended|from\s+above|please|now))?[!\s]*$',
    ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(
      r'^(please\s+)?(do|make|apply|implement)\s+(what\s+you\s+said|what\s+you\s+planned|what\s+you\s+proposed|those\s+suggestions|these\s+suggestions|the\s+suggested\s+changes|your\s+recommended\s+changes)(\s+(please|now))?[!\s]*$',
    ).hasMatch(normalized)) {
      return true;
    }
    final words = normalized.split(' ').where((word) => word.isNotEmpty);
    final hasGreeting = words.any(
      (word) => {'hi', 'hello', 'hey', 'thanks'}.contains(word),
    );
    final hasAction = _hasDirectActionRequest(normalized);
    return words.length <= 3 && hasGreeting && !hasAction;
  }

  static bool _looksLikeVerification(String normalized) {
    if (RegExp(
      r'\b(don t|do not|dont|without|no)\b.*\b(run|execute)?\s*(tests?|test suite|checks?|lint|analy[sz]e|build)\b',
    ).hasMatch(normalized)) {
      return false;
    }
    if (RegExp(
      r'\b(run|execute) (the )?(test suite|tests?|unit tests?|integration tests?|checks?|lint|analy[sz]e|build)\b',
    ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(
      r'\b(flutter analyze|flutter test|dart test|npm test|npm run test|pnpm test|yarn test|pytest|cargo test|go test)\b',
    ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(
      r'\b(check|see|verify|validate) (if|whether)? ?(the )?(build|tests?|checks?|lint|analy[sz]er?) (passes|pass|works|succeeds?)\b',
    ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(
      r'\b(does this|do these|will this|will these) (pass|passes) (tests?|checks?|the build)\b',
    ).hasMatch(normalized)) {
      return true;
    }
    return RegExp(
      r'\b(test this|verify|validate|lint|analyze|build it)\b',
    ).hasMatch(normalized);
  }

  static bool _looksLikeImplementationWithVerification(String normalized) {
    if (!_hasMutationRequest(normalized)) return false;
    return RegExp(
          r'\b(run|execute) (the )?(test suite|tests?|unit tests?|integration tests?|checks?|lint|analy[sz]e|build)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(flutter analyze|flutter test|dart test|npm test|npm run test|pnpm test|yarn test|pytest|cargo test|go test)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(verify|validate|check|see) (if|whether)? ?(the )?(build|tests?|checks?|lint|analy[sz]er?) (passes|pass|works|succeeds?)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(and|then)\s+(verify|validate|check)\b',
        ).hasMatch(normalized);
  }

  static bool _looksLikeOperationalCommand(String normalized) {
    if (_hasMutationRequest(normalized)) return false;
    return RegExp(
          r'\b(run|start|launch|serve|open|preview)\s+(the\s+)?(app|application|project|dev server|development server|server|frontend|backend|website|site|web app)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(start|launch|serve|preview)\s+(it|this|that)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(open|preview)\s+(localhost|127 0 0 1|0 0 0 0|the local (app|site|website|server))\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(install|update)\s+(dependencies|deps|packages|the dependencies|the deps)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(npm install|npm ci|pnpm install|yarn install|bun install|pip install|pip3 install|poetry install|bundle install|composer install|cargo fetch|go mod download|flutter pub get|dart pub get)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(run|execute|apply)\s+(the\s+)?(database\s+)?migrations?\b|\b(migrate|seed)\s+(the\s+)?(database|db)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(prisma migrate|alembic upgrade|rails db migrate|django migrate|python manage py migrate|python3 manage py migrate)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(commit|push|stage)\s+(the\s+)?(changes|current changes|work|everything)\b|\b(git commit|git push|git add)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(commit|stage|push)\s+and\s+(rebuild|build|deploy|publish|release)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(rebuild|build)\s+(the\s+)?(app|application|project|site|website|frontend|backend|desktop app|macos app)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(rebuild|build)\s+(the\s+)?(app|application|project)\s+(to|for|onto)\s+(my\s+)?(desktop|mac|macos)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(copy|refresh|replace)\s+(the\s+)?(rebuilt|fresh|new)?\s*(app|application|app bundle|macos app)\s+(to|on|onto)\s+(my\s+)?desktop\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(flutter build macos|xcodebuild|dart compile|npm run build|pnpm build|yarn build|bun run build)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(deploy|publish|release)\s+(the\s+)?(app|application|project|site|website|frontend|backend)\b|\b(vercel deploy|firebase deploy|wrangler deploy|netlify deploy|fly deploy|railway up)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(npm run dev|npm start|pnpm dev|yarn dev|bun dev|flutter run|dart run|python m http server|python3 m http server)\b',
        ).hasMatch(normalized);
  }

  static bool _looksLikeReadOnlyQuestion(String normalized) {
    if (_hasNoMutationConstraint(normalized) &&
        RegExp(
          r'\b(review|inspect|look|look at|take a look|check|tell me|show me|explain|summarize|describe)\b',
        ).hasMatch(normalized)) {
      return true;
    }
    if (_looksLikeInlineAnswerRequest(normalized)) return true;
    if (_isReadOnlyHelpQuestion(normalized)) return true;
    if (_isVagueInspectionRequest(normalized)) return true;
    if (_isVagueProblemOrMutationRequest(normalized)) return true;
    if (RegExp(r'^(what|why|how|where|when|who)\b').hasMatch(normalized)) {
      return true;
    }
    if (_hasDirectActionRequest(normalized)) return false;
    return RegExp(
      r'\b(explain|summarize|describe|show me|list|find|where is|what does|how does|tell me about|walk me through)\b',
    ).hasMatch(normalized);
  }

  static bool _looksLikeProductInceptionRequest(String normalized) {
    if (_requestsChatOnlyOutput(normalized)) return false;
    if (_hasExplicitFileOutputRequest(normalized)) return false;
    if (_hasExplicitExistingSurfaceMutation(normalized)) return false;
    if (_hasImplementationReadySignal(normalized)) return false;
    if (RegExp(
      r'\b(build|create|make|design)\s+(the\s+)?(app|application|project|site|website|frontend|backend)\s+(to|for|onto)\s+(my\s+)?(desktop|mac|macos)\b',
    ).hasMatch(normalized)) {
      return false;
    }

    final startsAsIdea = _hasBroadBuildLead(normalized);
    final namesProductIdea = _namesProductIdea(normalized);
    final exploresProductIdea = _exploresProductIdea(normalized);
    final broadObject = _hasBroadProductObject(normalized);
    final broadScope = _hasBroadScopeRequest(normalized);
    final discoveryPurpose = RegExp(
      r'\b(to|for)\s+(help|size|manage|track|plan|design|architect|quote|estimate|recommend|compare|validate|support|automate|analyze|analyse|customers?|clients?|users?|teams?)\b',
    ).hasMatch(normalized);
    final thinSpec = normalized.split(' ').length <= 16;
    final businessAudience = RegExp(
      r'\b(for|to help|to support)\s+(customers?|clients?|users?|teams?|businesses?|companies?|sales|support|ops|operations|engineers?|admins?)\b',
    ).hasMatch(normalized);
    final vagueDomainSpec = RegExp(
      r'\b(for|to)\s+(manage|track|plan|size|quote|estimate|recommend|compare|validate|support|automate|analyze|analyse|handle|organize|organise)\b',
    ).hasMatch(normalized);

    return (startsAsIdea || namesProductIdea || exploresProductIdea) &&
        (broadObject || broadScope || discoveryPurpose || businessAudience) &&
        (discoveryPurpose ||
            thinSpec ||
            businessAudience ||
            vagueDomainSpec ||
            broadScope ||
            !_hasImplementationReadySignal(normalized));
  }

  static bool _hasBroadBuildLead(String normalized) {
    return RegExp(
          r'^(i|we)\s+(want|need|would like|am trying|m trying|are trying)\s+to\s+(build|create|make|design|develop|prototype)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^(i|we)\s+(want|need|would like|am trying|m trying|are trying)\s+to\s+(figure out|scope|plan|design|architect)\s+(a|an|the)?\s*(new\s+)?(app|application|tool|product|platform|system|saas|dashboard|calculator|portal|workflow|solution|website|site|web app|mobile app|desktop app)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^(can|could|would|will)\s+you\s+(please\s+)?(help\s+me\s+)?(build|create|make|design|develop|prototype)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^(help\s+me|work\s+with\s+me|walk\s+me\s+through)\s+(build|create|make|design|develop|prototype)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^(build|create|make|design|develop|prototype)\s+(me\s+)?(a|an|the)?\b',
        ).hasMatch(normalized);
  }

  static bool _namesProductIdea(String normalized) {
    return RegExp(
          r'^(i|we)\s+(want|need|would like)\s+(a|an|the)?\s*(new\s+)?([a-z0-9]+\s+){0,3}(app|application|tool|product|platform|system|saas|dashboard|calculator|portal|workflow|solution|crm|cms|erp|website|site|web app|mobile app|desktop app)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^(i|we)\s+(have|had|got)\s+(a|an|the)?\s*(new\s+)?(idea|concept)\s+for\s+(a|an|the)?\s*(app|application|tool|product|platform|system|saas|dashboard|calculator|portal|workflow|solution|website|site|web app|mobile app|desktop app)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^(i|we)\s+(have|had|got)\s+(a|an|the)?\s*(new\s+)?(idea|concept)\s+for\b.*\b(app|application|tool|product|platform|system|saas|dashboard|calculator|portal|workflow|solution|crm|cms|erp|website|site|web app|mobile app|desktop app)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^(i|we)\s+(am|are|m|re)?\s*(thinking|considering)\s+(about|of)\s+(a|an|the)?\s*(new\s+)?(app|application|tool|product|platform|system|saas|dashboard|calculator|portal|workflow|solution|website|site|web app|mobile app|desktop app)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^(can|could|would|will)\s+you\s+(please\s+)?(help\s+me\s+)?(with|plan|scope|figure out)\s+(a|an|the)?\s*(new\s+)?(app|application|tool|product|platform|system|saas|dashboard|calculator|portal|workflow|solution|crm|cms|erp|website|site|web app|mobile app|desktop app)\b',
        ).hasMatch(normalized);
  }

  static bool _exploresProductIdea(String normalized) {
    return RegExp(
          r'^(can|could|would|will)\s+you\s+(please\s+)?(help\s+me\s+)?(figure out|scope|plan|think through|work through|talk through|design|architect)\b.*\b(app|application|tool|product|platform|system|saas|dashboard|calculator|portal|workflow|solution|website|site|web app|mobile app|desktop app)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^(help\s+me|work\s+with\s+me|walk\s+me\s+through)\s+(figure out|scope|plan|think through|work through|talk through|design|architect)\b.*\b(app|application|tool|product|platform|system|saas|dashboard|calculator|portal|workflow|solution|website|site|web app|mobile app|desktop app)\b',
        ).hasMatch(normalized);
  }

  static bool _hasBroadProductObject(String normalized) {
    return RegExp(
          r'\b(something|app|application|tool|product|platform|system|saas|dashboard|calculator|portal|workflow|solution|crm|cms|erp|internal tool|admin tool|website|site|web app|mobile app|desktop app)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b([a-z0-9]+\s+){0,3}(tracker|planner|manager|assistant|generator|analyzer|analyser|sizer|estimator|recommender|validator|visualizer|visualiser)\b',
        ).hasMatch(normalized);
  }

  static bool _hasBroadScopeRequest(String normalized) {
    return RegExp(
          r'\b(whole|entire|full|complete|end to end|end-to-end)\s+(app|application|tool|product|platform|system|saas|dashboard|portal|workflow|solution|website|site|web app|mobile app|desktop app|thing)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(the\s+)?(whole|entire|full|complete)\s+(thing|product|project)\b',
        ).hasMatch(normalized);
  }

  static bool _hasConcreteImplementationTarget(String normalized) {
    return RegExp(
          r'\b(component|screen|page|route|api|endpoint|service|class|function|widget|hook|provider|controller|model|schema|script|test|spec|readme|changelog|config)\b',
        ).hasMatch(normalized) ||
        _hasNormalizedFileTargetWithExtension(normalized, const {
          'md',
          'txt',
          'dart',
          'js',
          'ts',
          'tsx',
          'jsx',
          'py',
          'json',
          'yaml',
          'yml',
          'html',
          'css',
        });
  }

  static bool _hasFrameworkSignal(String normalized) {
    return RegExp(
      r'\b(flutter|dart|react|nextjs|next js|vue|svelte|angular|swiftui|swift|python|django|fastapi|node|express|typescript|javascript|tailwind|shadcn)\b',
    ).hasMatch(normalized);
  }

  static bool _hasImplementationReadySignal(String normalized) {
    return _hasExplicitFileOutputRequest(normalized) ||
        _hasExplicitExistingSurfaceMutation(normalized) ||
        _hasConcreteImplementationTarget(normalized) ||
        RegExp(
          r'\b(with|containing|include|including|that has|that includes)\b.*\b(component|screen|page|route|api|endpoint|service|class|function|widget|hook|provider|controller|model|schema|script|test|spec)\b',
        ).hasMatch(normalized) ||
        (_hasFrameworkSignal(normalized) &&
            RegExp(
              r'\b(component|screen|page|route|api|endpoint|service|class|function|widget|hook|provider|controller|model|schema|script|test|spec|static page|landing page|login page|settings screen|admin page)\b',
            ).hasMatch(normalized));
  }

  static bool _hasExplicitExistingSurfaceMutation(String normalized) {
    return RegExp(
          r'\b(add|edit|fix|update|change|modify|delete|remove|refactor|patch|implement)\s+(the\s+)?(existing\s+|current\s+)?(login|auth|dashboard|settings|profile|admin|checkout|billing|search|navigation|nav|sidebar|composer|drawer|rail|button|form|table|modal|screen|page|route|api|endpoint|component|widget|function|class|provider|controller|model|schema|tests?|bug|issue|error|failure)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(fix|debug|repair)\s+(the\s+)?[a-z0-9_ -]{0,40}\b(bug|issue|error|failure|crash|regression)\b',
        ).hasMatch(normalized);
  }

  static bool _looksLikeReviewRequest(String normalized) {
    if (_hasMutationRequest(normalized) &&
        !_hasNoMutationConstraint(normalized)) {
      return false;
    }
    return RegExp(
          r'\b(review|audit|inspect|look over|look at|summarize|summarise|explain|describe)\s+(the\s+)?(current\s+)?(changes|diff|git diff|patch|pull request|pr)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(what changed|what s changed|summarize what changed|summarise what changed)\b.*\b(changes|diff|git diff|patch|pull request|pr)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(review|audit|inspect|look over|look at)\s+(my|these|those)\s+(changes|edits|patches)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(code review|review pass|diff review|pr review)\b',
        ).hasMatch(normalized);
  }

  static bool _looksLikeAdvisoryQuestion(String normalized) {
    if (!normalized.endsWith('?')) return false;
    if (RegExp(
      r'^(can|could|would|will) you (please )?(fix|build|create|write|edit|add|delete|change|implement|apply|commit|install|generate|scaffold)\b',
    ).hasMatch(normalized)) {
      return false;
    }
    return RegExp(
          r'^(should|shouldn t|shouldn t we|should we|should i|do we need to|do i need to|would it be better to|is it worth|is there a reason to)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^(can|could|would) you (please )?(check|see|tell me|help me understand|figure out|look|look into|inspect) (if|whether|why|how)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^(do|does|did|is|are|was|were) .*\b(need|needs|should|worth|better|safe|correct|right)\b',
        ).hasMatch(normalized);
  }

  static bool _isReadOnlyHelpQuestion(String normalized) {
    return RegExp(
          r'^(can|could|would|will) you (please )?(help me )?(understand|explain|summarize|describe|look at|take a look|take a look at|make sense of|tell me about|walk me through|inspect)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^(explain|summarize|describe|walk me through|help me understand)\s+.*\b(failures?|errors?|issues?|problems?)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^(help me|can you help me|can you|could you) (understand|figure out|make sense of|trace|debug|debug why|debug what|debug how)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^(can|could|would|will) you (please )?(tell me|show me|walk me through|explain|help me understand) how to\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^(tell me|show me|walk me through|explain|help me understand) how to\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^(tell me|show me|walk me through|explain) (what|which) .*\b(would|should|could)\b.*\b(change|edit|modify|fix|implement)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^(can|could|would|will) you (please )?(tell me|show me|walk me through|explain) (what|which) .*\b(would|should|could)\b.*\b(change|edit|modify|fix|implement)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^(tell me|show me|walk me through|explain) (the )?(patch|changes?|edits?) .*\b(would|should|could)\b.*\b(make|apply|write|change|edit|modify|fix|implement)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'^(can|could|would|will) you (please )?(tell me|show me|walk me through|explain) (the )?(patch|changes?|edits?) .*\b(would|should|could)\b.*\b(make|apply|write|change|edit|modify|fix|implement)\b',
        ).hasMatch(normalized);
  }

  static bool _looksLikeInlineAnswerRequest(String normalized) {
    if (_hasExplicitFileOutputRequest(normalized)) return false;
    return RegExp(
      r'^(can|could|would|will)?\s*(you)?\s*(please)?\s*(write|draft|create|make|generate|prepare)\s+(me\s+)?(a|an|the)?\s*([a-z0-9]+\s+){0,3}(summary|overview|explanation|brief|report|table|comparison|list|risk list|risks?|recommendation|recommendations|analysis|changelog|release notes?)\b',
    ).hasMatch(normalized);
  }

  static bool _isVagueInspectionRequest(String normalized) {
    if (RegExp(
      r'^(make this better|improve this|clean this up|help me improve this|can you improve this)\??$',
    ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(
      r'^(take a look|look at this|review this|check this out)\??$',
    ).hasMatch(normalized)) {
      return true;
    }
    return false;
  }

  static bool _isVagueProblemOrMutationRequest(String normalized) {
    if (RegExp(
      r'^(fix it|fix this|fix that|make it work|make this work|make that work)\??$',
    ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(
      r'^(can you|could you|please|pls)?\s*(fix|repair|debug) (it|this|that|the app|the project)\??$',
    ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(
      r'^(it|this|that|the app|the project|everything) (is )?(broken|not working|failing|failing again|still broken)\??$',
    ).hasMatch(normalized)) {
      return true;
    }
    return false;
  }

  static bool _looksLikeDesignArtifactRequest(String normalized) {
    if (_requestsChatOnlyOutput(normalized)) return false;
    if (!_hasExplicitFileOutputRequest(normalized)) return false;
    if (!_hasDirectActionRequest(normalized)) return false;
    return _looksLikeDesignOrVisualArtifact(normalized);
  }

  static bool _looksLikeSourceFileOutputRequest(String normalized) {
    if (_requestsChatOnlyOutput(normalized)) return false;
    if (!_hasDirectActionRequest(normalized)) return false;
    if (!_hasNormalizedFileTargetWithExtension(normalized, const {
      'dart',
      'js',
      'ts',
      'tsx',
      'jsx',
      'py',
      'html',
      'css',
    })) {
      return false;
    }
    return RegExp(
      r'\b(component|screen|page|route|api|service|class|function|widget|hook|provider|controller|model|schema|script|test|spec|src|lib|app|backend|frontend)\b',
    ).hasMatch(normalized);
  }

  static bool _looksLikeDocumentArtifactFileOutputRequest(String normalized) {
    if (_requestsChatOnlyOutput(normalized)) return false;
    if (!_hasDirectActionRequest(normalized)) return false;
    if (!_hasNormalizedFileTargetWithExtension(normalized, const {
      'md',
      'txt',
    })) {
      return false;
    }
    return _looksLikeDesignOrVisualArtifact(normalized) ||
        RegExp(
          r'\b(business case|business use cases?|use cases?|company research|market research|industry research|competitive analysis|executive brief|customer brief|account plan|sales play|value proposition|roi analysis|case study)\b',
        ).hasMatch(normalized);
  }

  static bool _looksLikeDesignOrVisualArtifact(String normalized) {
    return RegExp(
          r'\b(topology|topology diagram|network topology|wan topology|lan topology|network diagram|architecture diagram|logical diagram|physical diagram|solution architecture|network architecture|network design|branch network design|campus network design|solution design|sizing plan|sizing recommendation|sizing table|validation table|architecture validation|network visualization|topology visualization|mermaid diagram)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(wan|lan|network|topology|architecture|solution|campus|branch)\s+(diagram|visualization|visual|table|matrix)\b',
        ).hasMatch(normalized);
  }

  static bool _looksLikeKnowledgeArtifactRequest(String normalized) {
    if (_requestsChatOnlyOutput(normalized)) return true;
    if (RegExp(
      r'\b(app|application|code|component|api|database|schema|bug|feature|file|repo|repository|project|package|module|class|function|screen|page|route)\b',
    ).hasMatch(normalized)) {
      return false;
    }
    final hasKnowledgeVerb = RegExp(
      r'\b(research|analyze|analyse|summarize|summarise|draft|create|build|generate|write|make|draw|show|design|architect|prepare|produce)\b',
    ).hasMatch(normalized);
    if (!hasKnowledgeVerb) return false;
    if (_looksLikeDesignOrVisualArtifact(normalized) ||
        RegExp(r'\b(charts?|visuals?)\b').hasMatch(normalized)) {
      return true;
    }
    return RegExp(
      r'\b(business use cases?|use cases?|business case|company research|market research|industry research|competitive analysis|executive brief|customer brief|account plan|sales play|value proposition|roi analysis|case study|charts?|visuals?|presentation outline|briefing)\b',
    ).hasMatch(normalized);
  }

  static bool _looksLikeEnterpriseAdvisoryRequest(String normalized) {
    final hasEnterpriseSubject = RegExp(
      r'\b(architecture|design|topology|network|wan|lan|switch(?:es)?|router(?:s)?|firewall(?:s)?|access points?|aps?|wi fi|wifi|poe|upoe|mGig|multigig|ldos|eol|eos|eox|end of (life|sale|support)|replacement pid|catalyst|meraki|cisco|model choice|sizing|throughput|ha|redundancy)\b',
      caseSensitive: false,
    ).hasMatch(normalized);
    if (!hasEnterpriseSubject) return false;

    return RegExp(
          r'\b(validate|verify|check|review|assess|evaluate|recommend|size|right[- ]?size|replace|refresh|migrate|choose|compare)\b',
          caseSensitive: false,
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(should|what|which|is|are|do we need|does this|will this)\b',
          caseSensitive: false,
        ).hasMatch(normalized);
  }

  static bool _looksLikePlanRequest(String normalized) {
    if (RegExp(
      r'\b(plan this out|create a plan|make a plan|write a plan|draft a plan|implementation plan|plan only)\b',
    ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(
          r'\b(draft|propose|outline|sketch) (the )?(patch|changes?|edits?|implementation)\b',
        ).hasMatch(normalized) &&
        _hasNoApplyConstraint(normalized)) {
      return true;
    }
    if (RegExp(
      r'\b(don t|do not|without|no)\b.*\b(change|modify|edit|write|apply|touch files|make changes)\b.*\b(yet|now|first)\b',
    ).hasMatch(normalized)) {
      return true;
    }
    return false;
  }

  static bool _hasDirectActionRequest(String normalized) {
    return RegExp(
      r'\b(build|create|write|edit|fix|run|test|make|add|delete|change|implement|verify|apply|commit|install|generate|scaffold)\b',
    ).hasMatch(normalized);
  }

  static bool _hasMutationRequest(String normalized) {
    if (RegExp(
      r'\b(write|edit|fix|add|delete|implement|apply|generate|scaffold|patch)\b',
    ).hasMatch(normalized)) {
      return true;
    }
    if (RegExp(
      r'\b(change|modify)\s+(the|this|that|a|an|new|[a-z0-9_./-]+)\b',
    ).hasMatch(normalized)) {
      return true;
    }
    return RegExp(
      r'^((can|could|would|will) you (please )?|please |pls )?(create|build|make)\s+(me\s+)?(the|this|that|a|an|new|[a-z0-9_./-]+)\b',
    ).hasMatch(normalized);
  }

  static bool _hasExplicitFileOutputRequest(String normalized) {
    return RegExp(
          r'\b(save|write|create|add|update|edit|commit)\b.*\b(file|files|readme|markdown file|md file|document|docs?|page)\b',
        ).hasMatch(normalized) ||
        _hasNormalizedFileTargetWithExtension(normalized, const {
          'md',
          'txt',
          'dart',
          'js',
          'ts',
          'tsx',
          'jsx',
          'py',
          'json',
          'yaml',
          'yml',
          'html',
          'css',
        }) ||
        RegExp(
          r'\b(save|write|create|add|update|edit|generate|draft|make)\b.*\b([a-z0-9_/-]+\s+)+(md|txt|dart|js|ts|tsx|jsx|py|json|ya?ml|html|css)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(to|in|into)\s+([a-z0-9_./-]+\.(md|txt|dart|js|ts|tsx|jsx|py|json|yaml|yml|html|css))\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(to|in|into)\s+([a-z0-9_/-]+\s+)+(md|txt|dart|js|ts|tsx|jsx|py|json|ya?ml|html|css)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(to|in|into)\s+([a-z0-9_/-]+\s+)?(readme|changelog)\s+(md|txt|markdown)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\b(write|add|update|edit)\s+.*\b(readme|docs?|documentation|changelog)\b',
        ).hasMatch(normalized);
  }

  static bool _hasNormalizedFileTargetWithExtension(
    String normalized,
    Set<String> extensions,
  ) {
    final words = normalized.split(' ').where((word) => word.isNotEmpty);
    final tokens = words.toList(growable: false);
    for (var index = 0; index < tokens.length; index++) {
      if (!extensions.contains(tokens[index])) continue;
      final start = index - 8 < 0 ? 0 : index - 8;
      final prefix = tokens.sublist(start, index).join(' ');
      if (!RegExp(
        r'\b(save|write|create|add|update|edit|generate|draft|make|to|in|into)\b',
      ).hasMatch(prefix)) {
        continue;
      }
      if (index == 0) continue;
      final previous = tokens[index - 1];
      if (const {
        'a',
        'an',
        'the',
        'as',
        'for',
        'with',
        'and',
        'or',
      }.contains(previous)) {
        continue;
      }
      return true;
    }
    return false;
  }

  static bool _hasNoMutationConstraint(String normalized) {
    return RegExp(
          r'\b(don t|do not|dont|without|no)\b.*\b(change|changes|modify|modifying|edit|edits|write|writes|create files?|save files?|apply|touch files|make changes)\b',
        ).hasMatch(normalized) ||
        RegExp(
          r'\bwithout\b.*\b(modifying|changing|editing|writing|creating files?|saving files?|applying)\b',
        ).hasMatch(normalized);
  }

  static bool _requestsChatOnlyOutput(String normalized) {
    final hasArtifactSubject = RegExp(
      r'\b(topology|topology diagram|network diagram|architecture diagram|logical diagram|physical diagram|mermaid diagram|chart|charts|visual|visuals|business case|brief|summary|report|recommendation|readme|readme md|changelog|changelog md|documentation|docs?|document|markdown|markdown content|file content)\b',
    ).hasMatch(normalized);
    if (!hasArtifactSubject) return false;
    final asksToCreateOrShow = RegExp(
      r'\b(create|build|generate|make|draw|show|draft|write)\b',
    ).hasMatch(normalized);
    if (!asksToCreateOrShow) return false;
    return _hasNoMutationConstraint(normalized) ||
        RegExp(
          r'\b(in chat|inline|as text|as markdown|in the chat|right here|without a file|without files|no file|no files|don t save|do not save|dont save)\b',
        ).hasMatch(normalized);
  }

  static bool _hasNoApplyConstraint(String normalized) {
    return _hasNoMutationConstraint(normalized) ||
        RegExp(
          r'\b(don t|do not|dont|without|no)\b.*\b(apply|applying|execute|executing|run|running)\b',
        ).hasMatch(normalized);
  }
}
