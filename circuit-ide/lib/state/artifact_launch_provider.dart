import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

typedef ArtifactLaunchHandler = Future<bool> Function(Uri uri);

final artifactLaunchProvider = Provider<ArtifactLaunchHandler>((ref) {
  return launchUrl;
});
