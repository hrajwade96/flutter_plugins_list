import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

const String projectPackage = 'project package';

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addFlag('help', negatable: false, abbr: 'h', help: 'Displays this help information.')
    ..addOption('output', abbr: 'o', help: 'Specify the output directory.')
    ..addFlag('json', negatable: false, help: 'Generate output in JSON format.')
    ..addFlag('csv', negatable: false, help: 'Generate output in CSV format.')
    ..addFlag('txt', negatable: false, help: 'Generate output in TXT format.');

  var argResults = parser.parse(arguments);

  if (argResults['help'] || argResults.arguments.isEmpty) {
    print('Usage: dart your_script.dart [options]');
    print(parser.usage);
    return;
  }

  final outputDir = argResults['output'] ?? 'output';
  final formats =<String,bool> {
    'json': argResults['json'],
    'csv': argResults['csv'],
    'txt': argResults['txt']
  };

  findDependencies(outputDir, formats);
}

Future<void> findDependencies(String outputDir, Map<String, bool> formats) async {
  final repoRoot = await findGitRepositoryRoot();
  final glob = Glob(path.join(repoRoot, '**/pubspec.yaml'));
  final pathsToIgnore = <String>[];
  final allDependencies = <String, Set<String>>{};

  await for (final FileSystemEntity entity in glob.list(followLinks: false)) {
    final relativeFilePath = path.relative(entity.path, from: repoRoot);
    final normalizedFilePath = path.normalize(relativeFilePath);

    if (entity is File && !shouldIgnore(normalizedFilePath, pathsToIgnore)) {
      try {
        final pubspecContent = await entity.readAsString();
        final doc = loadYaml(pubspecContent);
        if (doc is YamlMap && doc.containsKey('dependencies')) {
          _extractDependencies(doc['dependencies'], allDependencies);
        }
      } catch (e) {
        print('Error processing ${entity.path}: $e');
      }
    }
  }

  await _generateOutputFiles(allDependencies, formats, outputDir);
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

bool shouldIgnore(String filePath, List<String> pathsToIgnore) {
  if (pathsToIgnore.isEmpty) {
    return false; // Nothing to ignore if the list is empty
  }

  // Create a glob for each pattern and check if any match the file path
  for (var pattern in pathsToIgnore) {
    final glob = Glob(pattern);
    if (glob.matches(filePath)) {
      return true;
    }
  }
  return false;
}

void _extractDependencies(YamlMap dependencies, Map<String, Set<String>> allDependencies) {
  dependencies.forEach((key, value) {
    final packageName = key.toString();
    var versionInfo = value == null ? 'no version specified' : value.toString();
    if (value is YamlMap && value.containsKey('version')) {
      versionInfo = value['version'].toString();
    }
    allDependencies.putIfAbsent(packageName, () => <String>{});
    allDependencies[packageName]!.add(versionInfo);
  });
}

Future<void> _generateOutputFiles(Map<String, Set<String>> allDependencies, Map<String, bool> formats, String outputDir) async {
  final latestVersions = <String, String>{};
  for (var packageName in allDependencies.keys) {
    final latestVersion = await fetchLatestVersion(packageName, allDependencies[packageName].toString());
    latestVersions[packageName] = latestVersion;
  }

  final outputDirectory = Directory(outputDir);
  if (!await outputDirectory.exists()) {
    await outputDirectory.create(recursive: true);
  }

  if (formats['json']!) {
    await generateJsonFile(allDependencies, latestVersions, outputDirectory.path);
  }
  if (formats['csv']!) {
    await generateCsvFile(allDependencies, latestVersions, outputDirectory.path);
  }
  if (formats['txt']!) {
    await generateTextFile(allDependencies, latestVersions, outputDirectory.path);
  }
}

Future<String> fetchLatestVersion(String packageName, String versionInfo) async {
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

Future<void> generateJsonFile(Map<String, Set<String>> allDependencies, Map<String, String> latestVersions, String outputPath) async {
  final file = File(path.join(outputPath, 'dependencies_list.json'));
  final jsonContent = allDependencies.map((key, value) => MapEntry(key, {
    'current_versions': value.toList(),
    'latest_version': latestVersions[key] ?? projectPackage
  }));
  await file.writeAsString(jsonEncode(jsonContent));
}

Future<void> generateCsvFile(Map<String, Set<String>> allDependencies, Map<String, String> latestVersions, String outputPath) async {
  final file = File(path.join(outputPath, 'dependencies_list.csv'));
  final sink = file.openWrite();
  sink.writeln('Dependency Name,Current Versions,Latest Version');
  allDependencies.forEach((key, versions) {
    sink.writeln('$key,"${versions.join(', ')}",${latestVersions[key] ?? projectPackage}');
  });
  await sink.flush();
  await sink.close();
}

Future<void> generateTextFile(Map<String, Set<String>> allDependencies, Map<String, String> latestVersions, String outputPath) async {
  final file = File(path.join(outputPath, 'dependencies_list.txt'));
  final sink = file.openWrite();
  sink.writeln('Dependencies and their versions/details found across all pubspec.yaml files, including latest versions from pub.dev:');
  allDependencies.forEach((key, versions) {
    sink.writeln('$key: ${versions.join(', ')} (Latest as of now: ${latestVersions[key] ?? projectPackage})');
  });
  await sink.flush();
  await sink.close();
}
