import 'package:dio/dio.dart';

class GitHubTools {
  static const _baseUrl = 'https://api.github.com';

  String? _token;
  late final Dio _dio;

  GitHubTools() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'CircuitIDE/1.0',
      },
    ));
  }

  void configure({required String token}) {
    _token = token;
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  bool get isConfigured => _token != null && _token!.isNotEmpty;

  Future<String> execute(String toolName, Map<String, dynamic> args) async {
    if (!isConfigured) {
      return 'Error: GitHub token not configured. Set GITHUB_TOKEN or configure in settings.';
    }

    try {
      return switch (toolName) {
        'github_whoami' => _whoami(),
        'github_list_repos' => _listRepos(args),
        'github_get_repo' => _getRepo(args),
        'github_list_issues' => _listIssues(args),
        'github_get_issue' => _getIssue(args),
        'github_create_issue' => _createIssue(args),
        'github_close_issue' => _closeIssue(args),
        'github_list_prs' => _listPRs(args),
        'github_get_pr' => _getPR(args),
        'github_search_repos' => _searchRepos(args),
        'github_search_issues' => _searchIssues(args),
        'github_create_repo' => _createRepo(args),
        _ => throw ArgumentError('Unknown GitHub tool: $toolName'),
      };
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      if (status == 401) return 'Error: GitHub authentication failed. Check your token.';
      if (status == 403) return 'Error: GitHub rate limit or permission denied.';
      if (status == 404) return 'Error: GitHub resource not found.';
      return 'GitHub API error ($status): ${body ?? e.message}';
    } catch (e) {
      return 'Error: $e';
    }
  }

  Future<String> _whoami() async {
    final response = await _dio.get('/user');
    final user = response.data as Map<String, dynamic>;
    return 'Authenticated as: ${user['login']}\n'
        'Name: ${user['name'] ?? 'N/A'}\n'
        'Email: ${user['email'] ?? 'N/A'}\n'
        'Public repos: ${user['public_repos']}\n'
        'Followers: ${user['followers']}';
  }

  Future<String> _listRepos(Map<String, dynamic> args) async {
    final sort = args['sort'] as String? ?? 'updated';
    final perPage = args['per_page'] as int? ?? 30;

    final response = await _dio.get('/user/repos', queryParameters: {
      'sort': sort,
      'per_page': perPage,
      'type': 'owner',
    });

    final repos = response.data as List;
    if (repos.isEmpty) return 'No repositories found.';

    final lines = repos.map((r) {
      final repo = r as Map<String, dynamic>;
      final private_ = repo['private'] == true ? ' (private)' : '';
      final stars = repo['stargazers_count'] ?? 0;
      final lang = repo['language'] ?? 'Unknown';
      return '- ${repo['full_name']}$private_ [$lang] ★$stars\n'
          '  ${repo['description'] ?? 'No description'}';
    }).toList();

    return lines.join('\n');
  }

  Future<String> _getRepo(Map<String, dynamic> args) async {
    final owner = args['owner'] as String;
    final repo = args['repo'] as String;

    final response = await _dio.get('/repos/$owner/$repo');
    final r = response.data as Map<String, dynamic>;

    return 'Repository: ${r['full_name']}\n'
        'Description: ${r['description'] ?? 'N/A'}\n'
        'Language: ${r['language'] ?? 'N/A'}\n'
        'Stars: ${r['stargazers_count']} | Forks: ${r['forks_count']}\n'
        'Open issues: ${r['open_issues_count']}\n'
        'Default branch: ${r['default_branch']}\n'
        'Created: ${r['created_at']}\n'
        'Updated: ${r['updated_at']}\n'
        'URL: ${r['html_url']}';
  }

  Future<String> _listIssues(Map<String, dynamic> args) async {
    final owner = args['owner'] as String;
    final repo = args['repo'] as String;
    final state = args['state'] as String? ?? 'open';

    final response = await _dio.get('/repos/$owner/$repo/issues', queryParameters: {
      'state': state,
      'per_page': 30,
    });

    final issues = response.data as List;
    if (issues.isEmpty) return 'No $state issues found.';

    final lines = issues.where((i) => i['pull_request'] == null).map((i) {
      final issue = i as Map<String, dynamic>;
      final labels = (issue['labels'] as List?)
              ?.map((l) => (l as Map)['name'])
              .join(', ') ??
          '';
      return '#${issue['number']} [${issue['state']}] ${issue['title']}\n'
          '  Author: ${issue['user']?['login'] ?? 'N/A'} | Labels: ${labels.isEmpty ? 'none' : labels}';
    }).toList();

    return lines.isEmpty ? 'No $state issues found.' : lines.join('\n');
  }

  Future<String> _getIssue(Map<String, dynamic> args) async {
    final owner = args['owner'] as String;
    final repo = args['repo'] as String;
    final number = args['number'] as int;

    final response = await _dio.get('/repos/$owner/$repo/issues/$number');
    final issue = response.data as Map<String, dynamic>;

    final labels = (issue['labels'] as List?)
            ?.map((l) => (l as Map)['name'])
            .join(', ') ??
        'none';

    return '#${issue['number']} ${issue['title']}\n'
        'State: ${issue['state']}\n'
        'Author: ${issue['user']?['login'] ?? 'N/A'}\n'
        'Labels: $labels\n'
        'Created: ${issue['created_at']}\n'
        'Updated: ${issue['updated_at']}\n'
        '\n${issue['body'] ?? 'No description.'}';
  }

  Future<String> _createIssue(Map<String, dynamic> args) async {
    final owner = args['owner'] as String;
    final repo = args['repo'] as String;
    final title = args['title'] as String;
    final body = args['body'] as String? ?? '';

    final response = await _dio.post('/repos/$owner/$repo/issues', data: {
      'title': title,
      'body': body,
    });

    final issue = response.data as Map<String, dynamic>;
    return 'Created issue #${issue['number']}: ${issue['title']}\n'
        'URL: ${issue['html_url']}';
  }

  Future<String> _closeIssue(Map<String, dynamic> args) async {
    final owner = args['owner'] as String;
    final repo = args['repo'] as String;
    final number = args['number'] as int;

    await _dio.patch('/repos/$owner/$repo/issues/$number', data: {
      'state': 'closed',
    });

    return 'Issue #$number closed.';
  }

  Future<String> _listPRs(Map<String, dynamic> args) async {
    final owner = args['owner'] as String;
    final repo = args['repo'] as String;
    final state = args['state'] as String? ?? 'open';

    final response = await _dio.get('/repos/$owner/$repo/pulls', queryParameters: {
      'state': state,
      'per_page': 30,
    });

    final prs = response.data as List;
    if (prs.isEmpty) return 'No $state pull requests found.';

    final lines = prs.map((p) {
      final pr = p as Map<String, dynamic>;
      final draft = pr['draft'] == true ? ' [DRAFT]' : '';
      return '#${pr['number']}$draft ${pr['title']}\n'
          '  ${pr['head']?['ref'] ?? '?'} → ${pr['base']?['ref'] ?? '?'} | Author: ${pr['user']?['login'] ?? 'N/A'}';
    }).toList();

    return lines.join('\n');
  }

  Future<String> _getPR(Map<String, dynamic> args) async {
    final owner = args['owner'] as String;
    final repo = args['repo'] as String;
    final number = args['number'] as int;

    final response = await _dio.get('/repos/$owner/$repo/pulls/$number');
    final pr = response.data as Map<String, dynamic>;

    return '#${pr['number']} ${pr['title']}\n'
        'State: ${pr['state']}${pr['merged'] == true ? ' (merged)' : ''}${pr['draft'] == true ? ' [DRAFT]' : ''}\n'
        'Branch: ${pr['head']?['ref']} → ${pr['base']?['ref']}\n'
        'Author: ${pr['user']?['login'] ?? 'N/A'}\n'
        'Changed files: ${pr['changed_files']} | +${pr['additions']} -${pr['deletions']}\n'
        'Created: ${pr['created_at']}\n'
        'Updated: ${pr['updated_at']}\n'
        '\n${pr['body'] ?? 'No description.'}';
  }

  Future<String> _searchRepos(Map<String, dynamic> args) async {
    final query = args['query'] as String;

    final response = await _dio.get('/search/repositories', queryParameters: {
      'q': query,
      'per_page': 10,
    });

    final data = response.data as Map<String, dynamic>;
    final items = data['items'] as List;
    if (items.isEmpty) return 'No repositories found.';

    final lines = items.map((r) {
      final repo = r as Map<String, dynamic>;
      return '- ${repo['full_name']} ★${repo['stargazers_count']} [${repo['language'] ?? '?'}]\n'
          '  ${repo['description'] ?? 'No description'}';
    }).toList();

    return 'Found ${data['total_count']} repositories:\n\n${lines.join('\n')}';
  }

  Future<String> _searchIssues(Map<String, dynamic> args) async {
    final query = args['query'] as String;

    final response = await _dio.get('/search/issues', queryParameters: {
      'q': query,
      'per_page': 10,
    });

    final data = response.data as Map<String, dynamic>;
    final items = data['items'] as List;
    if (items.isEmpty) return 'No issues found.';

    final lines = items.map((i) {
      final issue = i as Map<String, dynamic>;
      final type = issue['pull_request'] != null ? 'PR' : 'Issue';
      return '- [$type] ${issue['repository_url']?.toString().split('/').sublist(4).join('/') ?? ''}'
          '#${issue['number']} ${issue['title']}\n'
          '  State: ${issue['state']} | Author: ${issue['user']?['login'] ?? 'N/A'}';
    }).toList();

    return 'Found ${data['total_count']} results:\n\n${lines.join('\n')}';
  }

  Future<String> _createRepo(Map<String, dynamic> args) async {
    final name = args['name'] as String;
    final description = args['description'] as String? ?? '';
    final private_ = args['private'] as bool? ?? false;

    final response = await _dio.post('/user/repos', data: {
      'name': name,
      'description': description,
      'private': private_,
      'auto_init': true,
    });

    final repo = response.data as Map<String, dynamic>;
    return 'Created repository: ${repo['full_name']}\n'
        'URL: ${repo['html_url']}';
  }
}
