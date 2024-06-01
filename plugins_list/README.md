# Flutter Plugins List

`flutter_plugins_list` is a powerful command-line tool designed to manage Flutter/Dart package dependencies by scanning `pubspec.yaml` 
files in your project directories. It helps you keep track of your dependencies and ensures they are up-to-date by fetching the latest versions from pub.dev.

## Features

- **Automatic Scanning**: Recursively scans all directories for `pubspec.yaml` files.
- **Version Fetching**: Retrieves the latest versions of dependencies from pub.dev.
- **Comprehensive Reports**: Generates a `dependencies_list.txt` , 'dependencies_list.csv' and 'dependencies_list.json' files listing all dependencies and their versions.

## Installation

To use `flutter_plugins_list`, you need to have Dart installed on your system. Follow these steps to install the tool:

### Step 1: Add to pubspec.yaml

Add the following to your project's `pubspec.yaml` file:

```yaml
dev_dependencies:
  flutter_plugins_list: ^1.0.3
```

### Step 2: 

Execute the command: 'flutter_plugins_list'