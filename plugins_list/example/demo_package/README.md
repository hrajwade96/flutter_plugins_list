# Flutter Plugins List Example

This is a demo package for demonstrating how to use the `flutter_plugins_list` tool. This tool scans your Flutter project for `pubspec.yaml` files, retrieves the latest versions of dependencies from pub.dev, and generates output files in CSV and JSON formats.

## Features

- **Automatic Scanning**: Recursively scans all directories for `pubspec.yaml` files.
- **Version Fetching**: Retrieves the latest versions of dependencies from pub.dev.
- **Comprehensive Reports**: Generates CSV and JSON reports listing all dependencies and their versions.

## Installation

To use this tool, you need to have Dart installed on your system. Add `flutter_plugins_list` as a dev dependency in your project's `pubspec.yaml`:

```yaml
dev_dependencies:
  flutter_plugins_list:^1.0.3
```

## Run command

```shell
flutter_plugins_list
```