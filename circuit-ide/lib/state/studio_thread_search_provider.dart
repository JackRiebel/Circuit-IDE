import 'package:flutter_riverpod/flutter_riverpod.dart';

enum StudioThreadStatusFilter { all, active, attention, completed }

class StudioThreadSearchState {
  final bool isOpen;
  final String query;
  final StudioThreadStatusFilter statusFilter;
  final bool showArchived;

  const StudioThreadSearchState({
    this.isOpen = false,
    this.query = '',
    this.statusFilter = StudioThreadStatusFilter.all,
    this.showArchived = false,
  });

  StudioThreadSearchState copyWith({
    bool? isOpen,
    String? query,
    StudioThreadStatusFilter? statusFilter,
    bool? showArchived,
  }) {
    return StudioThreadSearchState(
      isOpen: isOpen ?? this.isOpen,
      query: query ?? this.query,
      statusFilter: statusFilter ?? this.statusFilter,
      showArchived: showArchived ?? this.showArchived,
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
    state = state.copyWith(
      isOpen: false,
      query: '',
      statusFilter: StudioThreadStatusFilter.all,
      showArchived: false,
    );
  }

  void setQuery(String query) {
    state = state.copyWith(query: query);
  }

  void setStatusFilter(StudioThreadStatusFilter value) {
    state = state.copyWith(statusFilter: value);
  }

  void setShowArchived(bool value) =>
      state = state.copyWith(showArchived: value);
}

final studioThreadSearchProvider =
    NotifierProvider<StudioThreadSearchController, StudioThreadSearchState>(
      StudioThreadSearchController.new,
    );
