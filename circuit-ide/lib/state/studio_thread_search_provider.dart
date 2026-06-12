import 'package:flutter_riverpod/flutter_riverpod.dart';

class StudioThreadSearchState {
  final bool isOpen;
  final String query;

  const StudioThreadSearchState({this.isOpen = false, this.query = ''});

  StudioThreadSearchState copyWith({bool? isOpen, String? query}) {
    return StudioThreadSearchState(
      isOpen: isOpen ?? this.isOpen,
      query: query ?? this.query,
    );
  }
}

class StudioThreadSearchController extends Notifier<StudioThreadSearchState> {
  @override
  StudioThreadSearchState build() => const StudioThreadSearchState();

  void toggle() {
    state = state.copyWith(isOpen: !state.isOpen);
  }

  void open() {
    state = state.copyWith(isOpen: true);
  }

  void close() {
    state = state.copyWith(isOpen: false, query: '');
  }

  void setQuery(String query) {
    state = state.copyWith(query: query);
  }
}

final studioThreadSearchProvider =
    NotifierProvider<StudioThreadSearchController, StudioThreadSearchState>(
      StudioThreadSearchController.new,
    );
