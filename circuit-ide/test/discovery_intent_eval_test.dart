import 'package:circuit_ide/agent/tools/tool_registry.dart';
import 'package:circuit_ide/models/studio_shell.dart';
import 'package:circuit_ide/models/turn_intent.dart';
import 'package:circuit_ide/ui/studio/studio_message_sender.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'broad product ideas across ten domains start a non-mutating discovery',
    () {
      const prompts = [
        'I want to build a clinic scheduling platform for small practices.',
        'Help me design a field service dispatch tool for technicians.',
        'We need a customer onboarding portal for our SaaS customers.',
        'Could we create a school volunteer coordination app?',
        'I want to make an inventory planning dashboard for retail teams.',
        'Help us build a grant-tracking workflow for a nonprofit.',
        'We need a property maintenance request system for tenants.',
        'I want to create a travel approval tool for finance teams.',
        'Can we design a lab sample tracking application for researchers?',
        'Help me build a supplier risk review workspace for procurement.',
      ];

      for (final prompt in prompts) {
        final intent = IntentClassifier.classify(
          prompt,
          promptMode: StudioPromptMode.code,
          planModeEnabled: false,
        );
        expect(intent, TurnIntent.ask, reason: prompt);
        expect(
          studioToolModeForIntent(
            intent: intent,
            promptMode: StudioPromptMode.code,
            hasWorkspace: true,
            planModeEnabled: false,
          ),
          AgentToolMode.ask,
          reason: prompt,
        );
      }
    },
  );
}
