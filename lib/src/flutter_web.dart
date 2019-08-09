// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import 'sdk_manager.dart';

Logger _logger = Logger('flutter_web');

/// Handle provisioning package:flutter_web and related work.
class FlutterWebManager {
  final String sdkPath;

  Directory _projectDirectory;

  bool _initedFlutterWeb = false;

  FlutterWebManager(this.sdkPath) {
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
      await initFlutterWeb();
    } catch (e, s) {
      _logger.warning('Error initializing flutter web', e, s);
    }
  }

  Future<void> initFlutterWeb() async {
    if (_initedFlutterWeb) {
      return;
    }

    _logger.info('creating flutter web pubspec');
    String pubspec = createPubspec(true);
    await File(path.join(_projectDirectory.path, 'pubspec.yaml'))
        .writeAsString(pubspec);

    await _runPubGet();

    final String sdkVersion = SdkManager.sdk.version;

    // download and save the flutter_web.sum file
    String url = 'https://storage.googleapis.com/compilation_artifacts/'
        '$sdkVersion/flutter_web.sum';
    Uint8List summaryContents = await http.readBytes(url);
    await File(path.join(_projectDirectory.path, 'flutter_web.sum'))
        .writeAsBytes(summaryContents);

    _initedFlutterWeb = true;
  }

  String get summaryFilePath {
    return path.join(_projectDirectory.path, 'flutter_web.sum');
  }

  static final Set<String> _flutterWebImportPrefixes = <String>{
    'package:flutter_web',
    'package:flutter_web_ui',
    'package:flutter_web_test',
    'package:web_skin_dart',
    'package:web_skin',
    'package:js',
    'package:react',
  };

  bool usesFlutterWeb(Set<String> imports) {
    return imports.any((String import) {
      return _flutterWebImportPrefixes.any(
        (String prefix) => import.startsWith(prefix),
      );
    });
  }

  bool hasUnsupportedImport(Set<String> imports) {
    return getUnsupportedImport(imports) != null;
  }

  String getUnsupportedImport(Set<String> imports) {
    // TODO(devoncarew): Should we support a white-listed set of package:
    // imports?
    print('aaay');

    for (String import in imports) {
      // All dart: imports are ok;
      if (import.startsWith('dart:')) {
        continue;
      }

      // Currently we only allow flutter web imports.
      if (import.startsWith('package:')) {
        print('ha');
        print(import);
        if (_flutterWebImportPrefixes
            .any((String prefix) => import.startsWith(prefix))) {
          print('suhh dude');
          continue;
        }

        return import;
      }

      // Don't allow file imports.
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

    if (includeFlutterWeb) {
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
    }

    return content;
  }
}

/*
  react:
    path: ${Directory.current.path}/flutter_web/packages/flutter_web_ui
  over_react:
    path: ${Directory.current.path}/flutter_web/packages/flutter_web_ui
  web_skin:
    path: ${Directory.current.path}/flutter_web/packages/flutter_web_ui
  web_skin_dart:
    path: ${Directory.current.path}/flutter_web/packages/flutter_web_ui
 */