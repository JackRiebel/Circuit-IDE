import 'package:flutter_riverpod/flutter_riverpod.dart';

class Command {
  final String id;
  final String label;
  final String? shortcut;
  final String category;
  final void Function() action;

  const Command({
    required this.id,
    required this.label,
    this.shortcut,
    this.category = 'General',
    required this.action,
  });
}

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
    state = state.copyWith(
      allCommands: commands,
      filteredCommands: commands,
    );
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
      state = state.copyWith(
        query: query,
        filteredCommands: state.allCommands,
      );
      return;
    }

    final lower = query.toLowerCase();
    final filtered = state.allCommands.where((cmd) {
      return cmd.label.toLowerCase().contains(lower) ||
          cmd.category.toLowerCase().contains(lower);
    }).toList();

    state = state.copyWith(query: query, filteredCommands: filtered);
  }

  void execute(Command command) {
    close();
    command.action();
  }
}

final commandPaletteProvider =
    NotifierProvider<CommandPaletteNotifier, CommandPaletteState>(
  CommandPaletteNotifier.new,
);
