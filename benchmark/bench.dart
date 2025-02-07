// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library services.bench;

import 'dart:async';

import 'package:logging/logging.dart';

import 'package:dart_services/src/analysis_server.dart';
import 'package:dart_services/src/bench.dart';
import 'package:dart_services/src/common.dart';
import 'package:dart_services/src/compiler.dart';
import 'package:dart_services/src/flutter_web.dart';

void main(List<String> args) async {
  final bool json = args.contains('--json');

  final BenchmarkHarness harness = BenchmarkHarness(asJson: json);

  final projectManager = ProjectManager(sdkPath);
  final project = projectManager.createProjectWithoutId();

  await project.initFlutterWeb();

  var compiler = Compiler(sdkPath, projectManager);

  Logger.root.level = Level.WARNING;
  Logger.root.onRecord.listen((LogRecord record) {
    print(record);
    if (record.stackTrace != null) print(record.stackTrace);
  });

  final List<Benchmark> benchmarks = [
    AnalyzerBenchmark('hello', sampleCode, project),
    AnalyzerBenchmark('hellohtml', sampleCodeWeb, project),
    AnalyzerBenchmark('sunflower', _sunflower, project),
    AnalyzerBenchmark('spinning_square', _spinningSquare, project),
    AnalysisServerBenchmark('hello', sampleCode, project),
    AnalysisServerBenchmark('hellohtml', sampleCodeWeb, project),
    AnalysisServerBenchmark('sunflower', _sunflower, project),
    AnalysisServerBenchmark(
        'spinning_square', _spinningSquare, project),
    Dart2jsBenchmark('hello', sampleCode, compiler),
    Dart2jsBenchmark('hellohtml', sampleCodeWeb, compiler),
    Dart2jsBenchmark('sunflower', _sunflower, compiler),
    Dart2jsBenchmark('spinning_square', _spinningSquare, compiler),
    DevCompilerBenchmark('hello', sampleCode, compiler),
    DevCompilerBenchmark('hellohtml', sampleCodeWeb, compiler),
    DevCompilerBenchmark('sunflower', _sunflower, compiler),
    DevCompilerBenchmark('spinning_square', _spinningSquare, compiler),
  ];

  await harness.benchmark(benchmarks);
  await compiler.dispose();
}

class AnalyzerBenchmark extends Benchmark {
  final String source;
  AnalysisServerWrapper analysisServer;

  AnalyzerBenchmark(
      String name, this.source, Project project)
      : super('analyzer.$name') {
    analysisServer = AnalysisServerWrapper(sdkPath, project);
  }

  @override
  Future init() => analysisServer.init();

  @override
  Future perform() => analysisServer.analyze(source);

  @override
  Future tearDown() => analysisServer.shutdown();
}

class Dart2jsBenchmark extends Benchmark {
  final String source;
  final Compiler compiler;

  Dart2jsBenchmark(String name, this.source, this.compiler)
      : super('dart2js.$name');

  @override
  Future perform() {
    return compiler.compile(source).then((CompilationResults result) {
      if (!result.success) throw result;
    });
  }
}

class DevCompilerBenchmark extends Benchmark {
  final String source;
  final Compiler compiler;

  DevCompilerBenchmark(String name, this.source, this.compiler)
      : super('dartdevc.$name');

  @override
  Future perform() {
    return compiler.compileDDC(source).then((DDCCompilationResults result) {
      if (!result.success) throw result;
    });
  }
}

class AnalysisServerBenchmark extends Benchmark {
  final String source;
  final AnalysisServerWrapper analysisServer;

  AnalysisServerBenchmark(
      String name, this.source, Project project)
      : analysisServer = AnalysisServerWrapper(sdkPath, project),
        super('completion.$name');

  @override
  Future init() => analysisServer.init();

  @override
  Future perform() => analysisServer.complete(source, 30);

  @override
  Future tearDown() => analysisServer.shutdown();
}

final String _sunflower = '''
library sunflower;

import 'dart:html';
import 'dart:math' as math;

main() {
  new Sunflower();
}

class Sunflower {
  static const String ORANGE = "orange";
  static const SEED_RADIUS = 2;
  static const SCALE_FACTOR = 4;
  static const TAU = math.pi * 2;
  static const MAX_D = 300;

  CanvasRenderingContext2D ctx;
  num xc, yc;
  num seeds = 0;
  num PHI;

  Sunflower() {
    PHI = (math.sqrt(5) + 1) / 2;

    CanvasElement canvas = querySelector("#canvas");
    xc = yc = MAX_D / 2;
    ctx = canvas.getContext("2d");

    InputElement slider = querySelector("#slider");
    slider.onChange.listen((Event e) {
      seeds = int.parse(slider.value);
      drawFrame();
    });

    seeds = int.parse(slider.value);

    drawFrame();
  }

  // Draw the complete figure for the current number of seeds.
  void drawFrame() {
    ctx.clearRect(0, 0, MAX_D, MAX_D);
    for (var i=0; i<seeds; i++) {
      var theta = i * TAU / PHI;
      var r = math.sqrt(i) * SCALE_FACTOR;
      var x = xc + r * math.cos(theta);
      var y = yc - r * math.sin(theta);
      drawSeed(x,y);
    }
  }

  // Draw a small circle representing a seed centered at (x,y).
  void drawSeed(num x, num y) {
    ctx.beginPath();
    ctx.lineWidth = 2;
    ctx.fillStyle = ORANGE;
    ctx.strokeStyle = ORANGE;
    ctx.arc(x, y, SEED_RADIUS, 0, TAU, false);
    ctx.fill();
    ctx.closePath();
    ctx.stroke();
  }
}
''';

final _spinningSquare = '''
// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_web/material.dart';
import 'package:flutter_web_ui/ui.dart' as ui;

class SpinningSquare extends StatefulWidget {
  @override
  _SpinningSquareState createState() => new _SpinningSquareState();
}

class _SpinningSquareState extends State<SpinningSquare>
    with SingleTickerProviderStateMixin {
  AnimationController _animation;

  @override
  void initState() {
    super.initState();
    // We use 3600 milliseconds instead of 1800 milliseconds because 0.0 -> 1.0
    // represents an entire turn of the square whereas in the other examples
    // we used 0.0 -> math.pi, which is only half a turn.
    _animation = new AnimationController(
      duration: const Duration(milliseconds: 3600),
      vsync: this,
    )..repeat();
  }

  @override
  Widget build(BuildContext context) {
    return new RotationTransition(
        turns: _animation,
        child: new Container(
          width: 200.0,
          height: 200.0,
          color: const Color(0xFF00FF00),
        ));
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }
}

main() async {
  await ui.webOnlyInitializePlatform();
  runApp(new Center(child: new SpinningSquare()));
}
''';
