// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import 'sdk_manager.dart';

Logger _logger = Logger('flutter_web');

/// Handle provisioning package:flutter_web and related work.
class PackageManager {
  final String sdkPath;

  Directory _projectDirectory;

  bool _initedPackageManager = false;

  PackageManager(this.sdkPath) {
    _projectDirectory = Directory.systemTemp.createTempSync('dartpad');
    _init();
  }

  void dispose() {
    _projectDirectory.deleteSync(recursive: true);
  }

  Directory get projectDirectory => _projectDirectory;

  String get packagesFilePath => path.join(projectDirectory.path, '.packages');

  void _init() {
    // create a pubspec.yaml file
    String pubspec = createPubspec(false);
    File(path.join(_projectDirectory.path, 'pubspec.yaml'))
        .writeAsStringSync(pubspec);

    // create a .packages file
    final String packagesFileContents = '''
$_samplePackageName:lib/
''';
    File(path.join(_projectDirectory.path, '.packages'))
        .writeAsStringSync(packagesFileContents);

    // and create a lib/ folder for completeness
    Directory(path.join(_projectDirectory.path, 'lib')).createSync();
  }

  Future<void> warmup() async {
    try {
      await initPackageManager();
    } catch (e, s) {
      _logger.warning('Error initializing package manager', e, s);
    }
  }

  Future<void> initPackageManager() async {
    if (_initedPackageManager) {
      return;
    }

    _logger.info('creating pubspec');
    String pubspec = createPubspec(true);
    await File(path.join(_projectDirectory.path, 'pubspec.yaml'))
        .writeAsString(pubspec);

    await _runPubGet();

    _initedPackageManager = true;
  }

  static final Set<String> approvedImportPrefixes = <String>{
  'package:web_skin_dart',
  'package:web_skin',
  'package:js',
  'package:react',
  };

  bool hasUnsupportedImport(Set<String> imports) {
    return getUnsupportedImport(imports) != null;
  }

  String getUnsupportedImport(Set<String> imports) {
    for (String import in imports) {
      // All dart: imports are ok;
      if (import.startsWith('dart:')) {
        continue;
      }

      if (import.startsWith('package:')) {
        if (approvedImportPrefixes
            .any((String prefix) => import.startsWith(prefix))) {
          continue;
        }

        return import;
      }

      return import;
    }

    return null;
  }

  Future<void> _runPubGet() async {
    _logger.info('running pub get (${_projectDirectory.path})');

    ProcessResult result = await Process.run(
      path.join(sdkPath, 'bin', 'pub'),
      <String>['get', '--no-precompile'],
      workingDirectory: _projectDirectory.path,
    );

    _logger.info('${result.stdout}'.trim());

    if (result.exitCode != 0) {
      _logger.warning('pub get failed: ${result.exitCode}');
      _logger.warning(result.stderr);

      throw 'pub get failed: ${result.exitCode}';
    }
  }

  static const String _samplePackageName = 'dartpad_sample';

  static String createPubspec(bool includeFlutterWeb) {
    String content = '''
name: $_samplePackageName
''';

      content += '''
dependencies:
  react: ^4.4.2
  over_react: ^1.30.2
  web_skin:
    hosted:
      name: web_skin
      url: https://pub.workiva.org
    version: ^1.53.1
  web_skin_dart:
    hosted:
      name: web_skin_dart
      url: https://pub.workiva.org
    version: ^2.31.0

dev_dependencies:
    build_runner: ^1.0.0
    build_web_compilers: ^2.0.0

dependency_overrides:
  react:
    git:
      url: git@github.com:cleandart/react-dart.git
      ref: 5.1.0-wip
  over_react:
    git:
      url: git@github.com:Workiva/over_react.git
      ref: 3.1.0-wip
  web_skin_dart:
    git:
      url: git@github.com:Workiva/web_skin_dart.git
      ref: react-16-wip
  ''';

    return content;
  }
}
