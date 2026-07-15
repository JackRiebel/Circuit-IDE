import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Native, user-initiated directory selection for a Studio workspace.
///
/// Keeping the platform dialog behind this boundary gives every Studio entry
/// point the same behavior and lets desktop integration tests exercise the
/// visible project-opening flow without attempting to automate macOS's system
/// file dialog.
abstract interface class ProjectDirectoryPicker {
  Future<String?> chooseDirectory({String? initialDirectory});
}

class NativeProjectDirectoryPicker implements ProjectDirectoryPicker {
  const NativeProjectDirectoryPicker();

  @override
  Future<String?> chooseDirectory({String? initialDirectory}) =>
      FilePicker.platform.getDirectoryPath(initialDirectory: initialDirectory);
}

final projectDirectoryPickerProvider = Provider<ProjectDirectoryPicker>(
  (ref) => const NativeProjectDirectoryPicker(),
);
