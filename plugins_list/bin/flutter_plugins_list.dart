library flutter_plugins_list;
// ignore_for_file: avoid_dynamic_calls

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

const projectPackage = 'project package';

Future<String> _fetchLatestVersion(
    String packageName, String versionInfo) async {
  print('processing $packageName version info is $versionInfo');
  final url = Uri.parse('https://pub.dev/api/packages/$packageName');
  try {
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      print('Fetched latest version from pub.dev $packageName Response '
          '${jsonResponse['latest']['version'].toString()}');
      return jsonResponse['latest']['version'].toString();
    } else {
      return 'could not fetch, this could be a project package';
    }
  } catch (e) {
    return 'error';
  }
}

bool _shouldIgnore(String filePath, List<String> pathsToIgnore) =>
    pathsToIgnore.any((ignorePattern) {
      // Using Glob from 'package:glob/glob.dart' to match patterns
      final glob = Glob(ignorePattern);
      return glob.matches(filePath);
    });

Future<void> main() async {
  final repoRoot = await findGitRepositoryRoot();
  final glob = Glob(path.join(repoRoot, '**/pubspec.yaml'));

  final pathsToIgnore = <String>[];
  var versionInfo = '';
  final allDependencies = <String, Set<String>>{};

  print('Searching for pubspec.yaml files...');

  var fileCount = 0;

  await for (final FileSystemEntity entity in glob.list(followLinks: false)) {
    // Convert the file path to a relative path from the current directory
    final relativeFilePath = path.relative(entity.path, from: path.current);
    // Normalize the file path to ensure consistency in path format
    final normalizedFilePath = path.normalize(relativeFilePath);

    if (entity is File && !_shouldIgnore(normalizedFilePath, pathsToIgnore)) {
      fileCount++;
      print('Processing ${entity.path}...');
      try {
        final pubspecContent = await entity.readAsString();
        final doc = loadYaml(pubspecContent);

        if (doc is YamlMap && doc.containsKey('dependencies')) {
          final dependencies = doc['dependencies'];
          if (dependencies is YamlMap) {
            dependencies.forEach((key, value) {
              final packageName = key.toString();
              versionInfo = projectPackage;
              // Default value if the version is not specified
              if (value == null) {
                versionInfo = 'no version specified';
              } else if (value is String) {
                versionInfo = value;
              } else if (value is YamlMap) {
                if (value.containsKey('version')) {
                  versionInfo = value['version'].toString();
                } else {
                  versionInfo =
                      value.keys.map((k) => '$k: ${value[k]}').join(', ');
                }
              }

              allDependencies.putIfAbsent(packageName, () => <String>{});
              allDependencies[packageName]!.add(versionInfo);
            });
          }
        }
      } catch (e) {
        print('Error processing ${entity.path}: $e');
      }
    }
  }

  print('Processed $fileCount pubspec.yaml files.'
      ' Fetching latest versions...');

  final latestVersions = <String, String>{};
  for (var packageName in allDependencies.keys) {
    final latestVersion = await _fetchLatestVersion(
        packageName, allDependencies[packageName].toString());
    latestVersions[packageName] = latestVersion;
  }
  print('Writing to dependencies_list.txt...');

  final file = File('dependencies_list.txt');
  final sink = file.openWrite()
    ..writeln(
        'Dependencies and their versions/details found across all pubspec.yaml files, including latest versions from pub.dev:');
  allDependencies.forEach((packageName, versions) {
    final latestVersion = latestVersions[packageName] ?? projectPackage;
    sink.writeln('$packageName: ${versions.join(', ')} '
        '(Latest as of now: $latestVersion)');
  });

  await sink.flush();
  await sink.close();

  print(
      'Completed. Dependencies list has been written to dependencies_list.txt');
}

Future<String> findGitRepositoryRoot() async {
  try {
    var result = await Process.run('git', ['rev-parse', '--show-toplevel']);
    if (result.exitCode != 0) {
      throw Exception('git command failed: ${result.stderr}');
    }
    return result.stdout.toString().trim();
  } on ProcessException catch (e) {
    throw Exception('Failed to run git command: $e');
  }
}