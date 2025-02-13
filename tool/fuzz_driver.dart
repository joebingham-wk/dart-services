// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// This tool drives the services API with a large number of files and fuzz
/// test variations. This should be run over all of the co19 tests in the SDK
/// prior to each deployment of the server.

library services.fuzz_driver;

import 'dart:async';
import 'dart:io' as io;
import 'dart:math';

import 'package:dart_services/src/analysis_server.dart' as analysis_server;
import 'package:dart_services/src/api_classes.dart';
import 'package:dart_services/src/common.dart';
import 'package:dart_services/src/common_server.dart';
import 'package:dart_services/src/compiler.dart' as comp;
import 'package:dart_services/src/flutter_web.dart';
import 'package:rpc/rpc.dart';

bool _SERVER_BASED_CALL = false;
bool _VERBOSE = false;
bool _DUMP_SRC = false;
bool _DUMP_PERF = false;
bool _DUMP_DELTA = false;

CommonServer server;
ApiServer apiServer;
MockContainer container;
MockCache cache;
analysis_server.AnalysisServerWrapper analysisServer;

comp.Compiler compiler;

var random = Random(0);
var maxMutations = 2;
var iterations = 5;
String commandToRun = 'ALL';
bool dumpServerComms = false;

OperationType lastExecuted;
int lastOffset;

Future main(List<String> args) async {
  if (args.isEmpty) {
    print('''
Usage: slow_test path_to_test_collection
    [seed = 0]
    [mutations per iteration = 2]
    [iterations = 5]
    [name of command to test = ALL]
    [dump server communications = false]''');

    io.exit(1);
  }

  // TODO: Replace this with args package.
  int seed = 0;
  String testCollectionRoot = args[0];
  if (args.length >= 2) seed = int.parse(args[1]);
  if (args.length >= 3) maxMutations = int.parse(args[2]);
  if (args.length >= 4) iterations = int.parse(args[3]);
  if (args.length >= 5) commandToRun = args[4];
  if (args.length >= 6) dumpServerComms = args[5].toLowerCase() == 'true';
  String sdk = sdkPath;

  // Load the list of files.
  var fileEntities = <io.FileSystemEntity>[];
  if (io.FileSystemEntity.isDirectorySync(testCollectionRoot)) {
    io.Directory dir = io.Directory(testCollectionRoot);
    fileEntities = dir.listSync(recursive: true);
  } else {
    fileEntities = [io.File(testCollectionRoot)];
  }

  analysis_server.dumpServerMessages = false;

  int counter = 0;
  Stopwatch sw = Stopwatch()..start();

  print('About to setuptools');
  print(sdk);

  // Warm up the services.
  await setupTools(sdk);

  print('Setup tools done');

  // Main testing loop.
  for (var fse in fileEntities) {
    counter++;
    if (!fse.path.endsWith('.dart')) continue;

    try {
      print('Seed: $seed, '
          '${((counter / fileEntities.length) * 100).toStringAsFixed(2)}%, '
          'Elapsed: ${sw.elapsed}');

      random = Random(seed);
      seed++;
      await testPath(fse.path, analysisServer, compiler);
    } catch (e) {
      print(e);
      print('FAILED: ${fse.path}');

      // Try and re-cycle the services for the next test after the crash
      await setupTools(sdk);
    }
  }

  print('Shutting down');

  await analysisServer.shutdown();
  await server.shutdown();
}

/// Init the tools, and warm them up
Future setupTools(String sdkPath) async {
  print('Executing setupTools');
  await analysisServer?.shutdown();

  print('SdKPath: $sdkPath');

  ProjectManager projectManager = ProjectManager(sdkPath);

  final project = projectManager.createProjectWithoutId();

  container = MockContainer();
  cache = MockCache();
  server = CommonServer(sdkPath, projectManager, container, cache);
  await server.init();

  apiServer = ApiServer(apiPrefix: '/api', prettyPrint: true)..addApi(server);

  analysisServer =
      analysis_server.AnalysisServerWrapper(sdkPath, project);
  await analysisServer.init();

  print('Warming up analysis server');
  await analysisServer.warmup();

  print('Warming up compiler');
  compiler = comp.Compiler(sdkPath, projectManager);
  await compiler.warmup(projectId: project.id);
  print('SetupTools done');
}

Future testPath(String path, analysis_server.AnalysisServerWrapper wrapper,
    comp.Compiler compiler) async {
  var f = io.File(path);
  String src = f.readAsStringSync();

  print('Path, Compilation/ms, Analysis/ms, '
      'Completion/ms, Document/ms, Fixes/ms, Format/ms');

  for (int i = 0; i < iterations; i++) {
    // Run once for each file without mutation.
    num averageCompilationTime = 0;
    num averageAnalysisTime = 0;
    num averageCompletionTime = 0;
    num averageDocumentTime = 0;
    num averageFixesTime = 0;
    num averageFormatTime = 0;
    if (_DUMP_SRC) print(src);

    try {
      switch (commandToRun.toLowerCase()) {
        case 'all':
          averageCompilationTime = await testCompilation(src, compiler);
          averageCompletionTime = await testCompletions(src, wrapper);
          averageAnalysisTime = await testAnalysis(src, wrapper);
          averageDocumentTime = await testDocument(src, wrapper);
          averageFixesTime = await testFixes(src, wrapper);
          averageFormatTime = await testFormat(src);
          break;

        case 'complete':
          averageCompletionTime = await testCompletions(src, wrapper);
          break;
        case 'analyze':
          averageAnalysisTime = await testAnalysis(src, wrapper);
          break;

        case 'document':
          averageDocumentTime = await testDocument(src, wrapper);
          break;

        case 'compile':
          averageCompilationTime = await testCompilation(src, compiler);
          break;

        case 'fix':
          averageFixesTime = await testFixes(src, wrapper);
          break;

        case 'format':
          averageFormatTime = await testFormat(src);
          break;

        default:
          throw 'Unknown command';
      }
    } catch (e, stacktrace) {
      print('===== FAILING OP: $lastExecuted, offset: $lastOffset  =====');
      print(src);
      print('=====                                                 =====');
      print(e);
      print(stacktrace);
      print('===========================================================');

      rethrow;
    }

    print('$path-$i, '
        '${averageCompilationTime.toStringAsFixed(2)}, '
        '${averageAnalysisTime.toStringAsFixed(2)}, '
        '${averageCompletionTime.toStringAsFixed(2)}, '
        '${averageDocumentTime.toStringAsFixed(2)}, '
        '${averageFixesTime.toStringAsFixed(2)}, '
        '${averageFormatTime.toStringAsFixed(2)}');

    if (maxMutations == 0) break;

    // And then for the remainder with an increasing mutated file.
    int noChanges = random.nextInt(maxMutations);

    for (int j = 0; j < noChanges; j++) {
      src = mutate(src);
    }
  }
}

Future<num> testAnalysis(
    String src, analysis_server.AnalysisServerWrapper analysisServer) async {
  lastExecuted = OperationType.Analysis;
  Stopwatch sw = Stopwatch()..start();

  lastOffset = null;
  if (_SERVER_BASED_CALL) {
    SourceRequest request = SourceRequest();
    request.source = src;
    await withTimeOut(server.analyze(request));
    await withTimeOut(server.analyze(request));
  } else {
    await withTimeOut(analysisServer.analyze(src));
    await withTimeOut(analysisServer.analyze(src));
  }

  if (_DUMP_PERF) print('PERF: ANALYSIS: ${sw.elapsedMilliseconds}');
  return sw.elapsedMilliseconds / 2.0;
}

Future<num> testCompilation(String src, comp.Compiler compiler) async {
  lastExecuted = OperationType.Compilation;
  Stopwatch sw = Stopwatch()..start();

  lastOffset = null;
  if (_SERVER_BASED_CALL) {
    CompileRequest request = CompileRequest();
    request.source = src;
    await withTimeOut(server.compile(request));
  } else {
    await withTimeOut(compiler.compile(src));
  }

  if (_DUMP_PERF) print('PERF: COMPILATION: ${sw.elapsedMilliseconds}');
  return sw.elapsedMilliseconds;
}

Future<num> testDocument(
    String src, analysis_server.AnalysisServerWrapper analysisServer) async {
  lastExecuted = OperationType.Document;
  Stopwatch sw = Stopwatch()..start();
  for (int i = 0; i < src.length; i++) {
    Stopwatch sw2 = Stopwatch()..start();

    if (i % 1000 == 0 && i > 0) print('INC: $i docs completed');
    lastOffset = i;
    if (_SERVER_BASED_CALL) {
      SourceRequest request = SourceRequest();
      request.source = src;
      request.offset = i;
      log(await withTimeOut(server.document(request)));
    } else {
      log(await withTimeOut(analysisServer.dartdoc(src, i)));
    }
    if (_DUMP_PERF) print('PERF: DOCUMENT: ${sw2.elapsedMilliseconds}');
  }
  return sw.elapsedMilliseconds / src.length;
}

Future<num> testCompletions(
    String src, analysis_server.AnalysisServerWrapper wrapper) async {
  lastExecuted = OperationType.Completion;
  Stopwatch sw = Stopwatch()..start();
  for (int i = 0; i < src.length; i++) {
    Stopwatch sw2 = Stopwatch()..start();

    if (i % 1000 == 0 && i > 0) print('INC: $i completes');
    lastOffset = i;
    if (_SERVER_BASED_CALL) {
      SourceRequest request = SourceRequest()
        ..source = src
        ..offset = i;
      await withTimeOut(server.complete(request));
    } else {
      await withTimeOut(wrapper.complete(src, i));
    }
    if (_DUMP_PERF) print('PERF: COMPLETIONS: ${sw2.elapsedMilliseconds}');
  }
  return sw.elapsedMilliseconds / src.length;
}

Future<num> testFixes(
    String src, analysis_server.AnalysisServerWrapper wrapper) async {
  lastExecuted = OperationType.Fixes;
  Stopwatch sw = Stopwatch()..start();
  for (int i = 0; i < src.length; i++) {
    Stopwatch sw2 = Stopwatch()..start();

    if (i % 1000 == 0 && i > 0) print('INC: $i fixes');
    lastOffset = i;
    if (_SERVER_BASED_CALL) {
      SourceRequest request = SourceRequest();
      request.source = src;
      request.offset = i;
      await withTimeOut(server.fixes(request));
    } else {
      await withTimeOut(wrapper.getFixes(src, i));
    }
    if (_DUMP_PERF) print('PERF: FIXES: ${sw2.elapsedMilliseconds}');
  }
  return sw.elapsedMilliseconds / src.length;
}

Future<num> testFormat(String src) async {
  lastExecuted = OperationType.Format;
  Stopwatch sw = Stopwatch()..start();
  int i = 0;
  lastOffset = i;
  SourceRequest request = SourceRequest();
  request.source = src;
  request.offset = i;
  log(await withTimeOut(server.format(request)));
  return sw.elapsedMilliseconds;
}

Future<T> withTimeOut<T>(Future<T> f) {
  return f.timeout(Duration(seconds: 30));
}

String mutate(String src) {
  var chars = [
    '{',
    '}',
    '[',
    ']',
    "'",
    ',',
    '!',
    '@',
    '#',
    '\$',
    '%',
    '^',
    '&',
    ' ',
    '(',
    ')',
    'null ',
    'class ',
    'for ',
    'void ',
    'var ',
    'dynamic ',
    ';',
    'as ',
    'is ',
    '.',
    'import '
  ];
  String s = chars[random.nextInt(chars.length)];
  int i = random.nextInt(src.length);
  if (i == 0) i = 1;

  if (_DUMP_DELTA) {
    log('Delta: $s');
  }
  String newStr = src.substring(0, i - 1) + s + src.substring(i);
  return newStr;
}

class MockContainer implements ServerContainer {
  @override
  String get version => vmVersion;
}

class MockCache implements ServerCache {
  @override
  Future<String> get(String key) => Future.value(null);

  @override
  Future set(String key, String value, {Duration expiration}) => Future.value();

  @override
  Future remove(String key) => Future.value();

  @override
  Future<void> shutdown() => Future.value();
}

enum OperationType {
  Compilation,
  Analysis,
  Completion,
  Document,
  Fixes,
  Format
}

final int termWidth = io.stdout.hasTerminal ? io.stdout.terminalColumns : 200;

void log(dynamic obj) {
  if (_VERBOSE) {
    print('${DateTime.now()} $obj');
  }
}
