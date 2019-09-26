// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// This library is a wrapper around the Dart to JavaScript (dart2js) compiler.
library services.compiler;

import 'dart:async';
import 'dart:io';

import 'package:bazel_worker/driver.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

import 'common.dart';
import 'flutter_web.dart';
import 'sdk_manager.dart';

Logger _logger = Logger('compiler');

/// An interface to the dart2js compiler. A compiler object can process one
/// compile at a time.
class Compiler {
  final String sdkPath;
  final ProjectManager projectManager;

  final BazelWorkerDriver _ddcDriver;
  String _sdkVersion;

  Compiler(this.sdkPath, this.projectManager)
      : _ddcDriver = BazelWorkerDriver(
            () => Process.start(path.join(sdkPath, 'bin', 'dartdevc'),
                <String>['--persistent_worker']),
            maxWorkers: 1) {
    _sdkVersion = SdkManager.sdk.version;
  }

  /// The version of the SDK this copy of dart2js is based on.
  String get version {
    return File(path.join(sdkPath, 'version')).readAsStringSync().trim();
  }

  Future<CompilationResults> warmup({bool useHtml = false, @required String projectId}) {
    return compile(useHtml ? sampleCodeWeb : sampleCode, projectId: projectId);
  }

  /// Compile the given string and return the resulting [CompilationResults].
  Future<CompilationResults> compile(
    String input, {
    bool returnSourceMap = false,
    @required String projectId,
  }) async {
    Directory temp = await Directory.systemTemp.createTemp('dartpad');

    try {
      List<String> arguments = <String> ['run', 'build_runner',
      'build', '-r', '-o${temp.path}'];

      final project = projectManager.createProjectIfNecessary(projectId);

      String compileTarget = path.join(project.projectDirectory
          .path, 'web', kMainDart);
      File mainDart = File(compileTarget);
      await mainDart.create(recursive: true);
      await mainDart.writeAsString(input);

      File mainJs = File(path.join(temp.path, 'web', '$kMainDart.js'));
      File mainSourceMap = File(path.join(temp.path, 'web', '$kMainDart.js'
          '.map'));

      final String pubPath = path.join(sdkPath, 'bin', 'pub');

      _logger.info('About to exec: $pubPath $arguments');

      ProcessResult result = Process.runSync(pubPath, arguments, workingDirectory:
          project.projectDirectory.path);

      if (result.exitCode != 0) {
        _logger.warning(result.stderr);
        final CompilationResults results =
            CompilationResults(problems: <CompilationProblem>[
          CompilationProblem._(result.stdout as String),
        ]);
        return results;
      } else {
        String sourceMap;
        if (returnSourceMap && await mainSourceMap.exists()) {
          sourceMap = await mainSourceMap.readAsString();
        }
        final CompilationResults results = CompilationResults(
          compiledJS: await mainJs.readAsString(),
          sourceMap: sourceMap,
        );
        return results;
      }
    } catch (e, st) {
      _logger.warning('Compiler failed: $e\n$st');
      rethrow;
    } finally {
      await temp.delete(recursive: true);
      _logger.info('temp folder removed: ${temp.path}');
    }
  }

  /// Compile the given string and return the resulting [DDCCompilationResults].
  Future<DDCCompilationResults> compileDDC(String input, String sessionId)
  async {
    Directory dir =
        Directory('${Directory.current.path}/dartpadSessionCache/$sessionId');
    await dir.create(recursive: true);

    try {
      List<String> arguments = <String>[
        '--modules=amd',
      ];

      print('creating dir');
      print('path is ${dir.path}');
      String compileTarget = path.join(dir.path, kMainDart);
      File mainDart = File(compileTarget);
      await mainDart.writeAsString(input);

//      final pubspecInput = _generatePubspec(imports);
//      File pubspec = File(path.join(dir.path, 'pubspec.yaml'));
//      await pubspec.writeAsString(pubspecInput);


      arguments.addAll(<String>['-o', path.join(dir.path, '$kMainDart.js')]);
      arguments.add('--single-out-file');
      arguments.addAll(<String>['--module-name', 'dartpad_main']);
      arguments.add(compileTarget);
      arguments.addAll(<String>['--library-root', dir.path]);

      File mainJs = File(path.join(dir.path, '$kMainDart.js'));

      _logger.info('About to exec dartdevc with:  $arguments');

      final WorkResponse response =
          await _ddcDriver.doWork(WorkRequest()..arguments.addAll(arguments));

      if (response.exitCode != 0) {
        return DDCCompilationResults.failed(<CompilationProblem>[
          CompilationProblem._(response.output),
        ]);
      } else {
        final DDCCompilationResults results = DDCCompilationResults(
          compiledJS: await mainJs.readAsString(),
          modulesBaseUrl: 'https://storage.googleapis.com/'
              'compilation_artifacts/$_sdkVersion/',
        );
        return results;
      }
    } catch (e, st) {
      _logger.warning('Compiler failed: $e\n$st');
      rethrow;
    } finally {
//      await dir.delete(recursive: true);
      _logger.info('dir folder removed: ${dir.path}');
    }
  }

  Future<void> dispose() => _ddcDriver.terminateWorkers();

//  String _generatePubspec(List<String> inputs) {
//    return
//  }
}

/// The result of a dart2js compile.
class CompilationResults {
  final String compiledJS;
  final String sourceMap;
  final List<CompilationProblem> problems;

  CompilationResults({
    this.compiledJS,
    this.problems = const <CompilationProblem>[],
    this.sourceMap,
  });

  bool get hasOutput => compiledJS != null && compiledJS.isNotEmpty;

  /// This is true if there were no errors.
  bool get success => problems.isEmpty;

  @override
  String toString() => success
      ? 'CompilationResults: Success'
      : 'Compilation errors: ${problems.join('\n')}';
}

/// The result of a DDC compile.
class DDCCompilationResults {
  final String compiledJS;
  final String modulesBaseUrl;
  final List<CompilationProblem> problems;

  DDCCompilationResults({this.compiledJS, this.modulesBaseUrl})
      : problems = const <CompilationProblem>[];

  DDCCompilationResults.failed(this.problems)
      : compiledJS = null,
        modulesBaseUrl = null;

  bool get hasOutput => compiledJS != null && compiledJS.isNotEmpty;

  /// This is true if there were no errors.
  bool get success => problems.isEmpty;
  @override
  String toString() => success
      ? 'CompilationResults: Success'
      : 'Compilation errors: ${problems.join('\n')}';
}

/// An issue associated with [CompilationResults].
class CompilationProblem implements Comparable<CompilationProblem> {
  final String message;

  CompilationProblem._(this.message);

  @override
  int compareTo(CompilationProblem other) => message.compareTo(other.message);

  @override
  String toString() => message;
}
