import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

const projectPackage = 'project package';

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

Future<String> fetchLatestVersion(
    String packageName, String versionInfo) async {
  final url = Uri.parse('https://pub.dev/api/packages/$packageName');
  try {
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return jsonResponse['latest']['version'].toString();
    } else {
      return 'Could not fetch, this could be a project package';
    }
  } catch (e) {
    return 'Error';
  }
}

bool shouldIgnore(String filePath, List<String> pathsToIgnore) =>
    pathsToIgnore.any((ignorePattern) {
      final glob = Glob(ignorePattern);
      return glob.matches(filePath);
    });

Future<void> findDependencies() async {
  final repoRoot = await findGitRepositoryRoot();
  final glob = Glob(path.join(repoRoot, '**/pubspec.yaml'));

  final pathsToIgnore = <String>[];
  var versionInfo = '';
  final allDependencies = <String, Set<String>>{};

  await for (final FileSystemEntity entity in glob.list(followLinks: false)) {
    final relativeFilePath = path.relative(entity.path, from: path.current);
    final normalizedFilePath = path.normalize(relativeFilePath);

    if (entity is File && !shouldIgnore(normalizedFilePath, pathsToIgnore)) {
      try {
        final pubspecContent = await entity.readAsString();
        final doc = loadYaml(pubspecContent);

        if (doc is YamlMap && doc.containsKey('dependencies')) {
          final dependencies = doc['dependencies'];
          if (dependencies is YamlMap) {
            dependencies.forEach((key, value) {
              final packageName = key.toString();
              versionInfo = projectPackage;
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

  final latestVersions = <String, String>{};
  for (var packageName in allDependencies.keys) {
    final latestVersion = await fetchLatestVersion(
        packageName, allDependencies[packageName].toString());
    latestVersions[packageName] = latestVersion;
  }

  await generateCsvFile(allDependencies, latestVersions);
  await generateJsonFile(allDependencies, latestVersions);
  await generateTextFile(allDependencies, latestVersions);
}

Future<void> generateCsvFile(Map<String, Set<String>> allDependencies,
    Map<String, String> latestVersions) async {
  final outputDir = Directory('output');
  if (!await outputDir.exists()) {
    await outputDir.create();
  }
  final csvFile = File(path.join(outputDir.path, 'dependencies_list.csv'));
  final sink = csvFile.openWrite();
  sink.writeln('Dependency Name,Current Version(s),Latest Version');

  allDependencies.forEach((packageName, versions) {
    final latestVersion = latestVersions[packageName] ?? projectPackage;
    sink.writeln('$packageName,${versions.join(' ')},$latestVersion');
  });

  await sink.flush();
  await sink.close();
}

Future<void> generateJsonFile(Map<String, Set<String>> allDependencies,
    Map<String, String> latestVersions) async {
  final outputDir = Directory('output');
  if (!await outputDir.exists()) {
    await outputDir.create();
  }
  final jsonFile = File(path.join(outputDir.path, 'dependencies_list.json'));
  final jsonContent = <String, dynamic>{};

  allDependencies.forEach((packageName, versions) {
    jsonContent[packageName] = {
      'current_versions': versions.toList(),
      'latest_version': latestVersions[packageName] ?? projectPackage,
    };
  });

  await jsonFile.writeAsString(jsonEncode(jsonContent));
}

Future<void> generateTextFile(Map<String, Set<String>> allDependencies,
    Map<String, String> latestVersions) async {
  final outputDir = Directory('output');
  if (!await outputDir.exists()) {
    await outputDir.create();
  }
  final txtFile = File(path.join(outputDir.path, 'dependencies_list.txt'));
  final sink = txtFile.openWrite();
  sink.writeln(
      'Dependencies and their versions/details found across all pubspec.yaml files, including latest versions from pub.dev:');
  allDependencies.forEach((packageName, versions) {
    final latestVersion = latestVersions[packageName] ?? projectPackage;
    sink.writeln(
        '$packageName: ${versions.join(', ')} (Latest as of now: $latestVersion)');
  });

  await sink.flush();
  await sink.close();
}

Future<void> main() async {
  await findDependencies();
}
