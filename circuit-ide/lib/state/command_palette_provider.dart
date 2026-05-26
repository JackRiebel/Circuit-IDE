import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/command_descriptor.dart';

typedef Command = CommandDescriptor;

class CommandPaletteState {
  final bool isOpen;
  final String query;
  final List<Command> allCommands;
  final List<Command> filteredCommands;

  const CommandPaletteState({
    this.isOpen = false,
    this.query = '',
    this.allCommands = const [],
    this.filteredCommands = const [],
  });

  CommandPaletteState copyWith({
    bool? isOpen,
    String? query,
    List<Command>? allCommands,
    List<Command>? filteredCommands,
  }) {
    return CommandPaletteState(
      isOpen: isOpen ?? this.isOpen,
      query: query ?? this.query,
      allCommands: allCommands ?? this.allCommands,
      filteredCommands: filteredCommands ?? this.filteredCommands,
    );
  }
}

class CommandPaletteNotifier extends Notifier<CommandPaletteState> {
  @override
  CommandPaletteState build() => const CommandPaletteState();

  void registerCommands(List<Command> commands) {
    state = state.copyWith(allCommands: commands, filteredCommands: commands);
  }

  void toggle() {
    state = state.copyWith(
      isOpen: !state.isOpen,
      query: '',
      filteredCommands: state.allCommands,
    );
  }

  void open() {
    state = state.copyWith(
      isOpen: true,
      query: '',
      filteredCommands: state.allCommands,
    );
  }

  void close() {
    state = state.copyWith(isOpen: false, query: '');
  }

  void filter(String query) {
    if (query.isEmpty) {
      state = state.copyWith(query: query, filteredCommands: state.allCommands);
      return;
    }

    final lower = _normalize(query);
    final filtered =
        state.allCommands.where((cmd) {
          return _normalize(cmd.title).contains(lower) ||
              _normalize(cmd.category).contains(lower) ||
              (cmd.description == null
                  ? false
                  : _normalize(cmd.description!).contains(lower));
        }).toList()..sort((a, b) {
          final aTitle = _normalize(a.title).startsWith(lower) ? 0 : 1;
          final bTitle = _normalize(b.title).startsWith(lower) ? 0 : 1;
          if (aTitle != bTitle) return aTitle.compareTo(bTitle);
          return a.title.compareTo(b.title);
        });

    state = state.copyWith(query: query, filteredCommands: filtered);
  }

  void execute(Command command) {
    if (!command.enabled) return;
    close();
    command.run();
  }

  String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }
}

final commandPaletteProvider =
    NotifierProvider<CommandPaletteNotifier, CommandPaletteState>(
      CommandPaletteNotifier.new,
    );
