import '../../services/lsdf_index_service.dart';

class LsdfContextLoader {
  static Future<String> load(String workingDir) async {
    final service = LsdfIndexService(rootPath: workingDir);
    await service.generate();
    final context = await service.loadPromptContext();
    if (context.isEmpty) return _protocolOnly;

    return '''
$_protocolOnly

## Current L-SDF Map

${context.content}
''';
  }

  static const _protocolOnly = '''
## L-SDF Token-Saving Protocol

This workspace has compact L-SDF structural indexes. To reduce token use, prefer this navigation order:

1. Read `project.lsdf` to understand top-level layout.
2. Read the nearest `INDEX.lsdf` before opening source files.
3. Read `INDEX.detail.lsdf` when signatures, imports, or source paths are needed.
4. Open raw source only when implementation bodies or exact edits are required.
5. After creating, deleting, renaming, or structurally editing code, keep the relevant L-SDF indexes current.

Use `lsdf_read_index` for these compact maps whenever possible.

L-SDF sigils: `^` project, `@` entity/file/class, `!` function, `~` dependency, `?` schema, `\$` annotation.
''';
}
