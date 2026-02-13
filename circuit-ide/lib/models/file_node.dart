class FileNode {
  final String name;
  final String path;
  final bool isDirectory;
  final bool isExpanded;
  final List<FileNode> children;
  final int depth;
  final bool isHidden;

  const FileNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.isExpanded = false,
    this.children = const [],
    this.depth = 0,
    this.isHidden = false,
  });

  FileNode copyWith({
    bool? isExpanded,
    List<FileNode>? children,
  }) {
    return FileNode(
      name: name,
      path: path,
      isDirectory: isDirectory,
      isExpanded: isExpanded ?? this.isExpanded,
      children: children ?? this.children,
      depth: depth,
      isHidden: isHidden,
    );
  }

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }
}
