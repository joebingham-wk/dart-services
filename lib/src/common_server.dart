// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library services.common_server;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dartis/dartis.dart' as redis;
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:pedantic/pedantic.dart';
import 'package:quiver/cache.dart';
import 'package:rpc/rpc.dart';
import 'package:shelf_cookie/shelf_cookie.dart';

import '../version.dart';
import 'analysis_server.dart';
import 'api_classes.dart';
import 'common.dart';
import 'compiler.dart';
import 'flutter_web.dart';
import 'sdk_manager.dart';

final Duration _standardExpiration = Duration(hours: 1);
final Logger log = Logger('common_server');

abstract class ServerCache {
  Future<String> get(String key);

  Future<void> set(String key, String value, {Duration expiration});

  Future<void> remove(String key);

  Future<void> shutdown();
}

abstract class ServerContainer {
  String get version;
}

class SummaryText {
  String text;

  SummaryText.fromString(this.text);
}

/// A redis-backed implementation of [ServerCache].
class RedisCache implements ServerCache {
  redis.Client redisClient;
  redis.Connection _connection;

  final String redisUriString;

  // Version of the server to add with keys.
  final String serverVersion;

  // pseudo-random is good enough.
  final Random randomSource = Random();
  static const int _connectionRetryBaseMs = 250;
  static const int _connectionRetryMaxMs = 60000;
  static const Duration cacheOperationTimeout = Duration(milliseconds: 10000);

  RedisCache(this.redisUriString, this.serverVersion) {
    _reconnect();
  }

  Completer<void> _connected = Completer<void>();

  /// Completes when and if the redis server connects.  This future is reset
  /// on disconnection.  Mostly for testing.
  Future<void> get connected => _connected.future;

  Completer<void> _disconnected = Completer<void>()..complete();

  /// Completes when the server is disconnected (begins completed).  This
  /// future is reset on connection.  Mostly for testing.
  Future<void> get disconnected => _disconnected.future;

  String __logPrefix;

  String get _logPrefix =>
      __logPrefix ??= 'RedisCache [$redisUriString] ($serverVersion)';

  bool _isConnected() => redisClient != null && !_isShutdown;
  bool _isShutdown = false;

  /// If you will no longer be using the [RedisCache] instance, call this to
  /// prevent reconnection attempts.  All calls to get/remove/set on this object
  /// will return null after this.  Future completes when disconnection is complete.
  @override
  Future<void> shutdown() {
    log.info('$_logPrefix: shutting down...');
    _isShutdown = true;
    redisClient?.disconnect();
    return disconnected;
  }

  /// Call when an active connection has disconnected.
  void _resetConnection() {
    assert(_connected.isCompleted && !_disconnected.isCompleted);
    _connected = Completer<void>();
    _connection = null;
    redisClient = null;
    _disconnected.complete();
  }

  /// Call when a new connection is established.
  void _setUpConnection(redis.Connection newConnection) {
    assert(_disconnected.isCompleted && !_connected.isCompleted);
    _disconnected = Completer<void>();
    _connection = newConnection;
    redisClient = redis.Client(_connection);
    _connected.complete();
  }

  /// Begin a reconnection loop asynchronously to maintain a connection to the
  /// redis server.  Never stops trying until shutdown() is called.
  void _reconnect([int retryTimeoutMs = _connectionRetryBaseMs]) {
    if (_isShutdown) {
      return;
    }
    log.info('$_logPrefix: reconnecting to $redisUriString...');
    int nextRetryMs = retryTimeoutMs;
    if (retryTimeoutMs < _connectionRetryMaxMs / 2) {
      // 1 <= (randomSource.nextDouble() + 1) < 2
      nextRetryMs = (retryTimeoutMs * (randomSource.nextDouble() + 1)).toInt();
    }
    redis.Connection.connect(redisUriString)
        .then((redis.Connection newConnection) {
          log.info('$_logPrefix: Connected to redis server');
          _setUpConnection(newConnection);
          // If the client disconnects, discard the client and try to connect again.
          newConnection.done.then((_) {
            _resetConnection();
            log.warning('$_logPrefix: connection terminated, reconnecting');
            _reconnect();
          }).catchError((dynamic e) {
            _resetConnection();
            log.warning(
                '$_logPrefix: connection terminated with error $e, reconnecting');
            _reconnect();
          });
        })
        .timeout(Duration(milliseconds: _connectionRetryMaxMs))
        .catchError((_) {
          log.severe(
              '$_logPrefix: Unable to connect to redis server, reconnecting in ${nextRetryMs}ms ...');
          Future<void>.delayed(Duration(milliseconds: nextRetryMs)).then((_) {
            _reconnect(nextRetryMs);
          });
        });
  }

  /// Build a key that includes the server version, and Dart SDK Version.
  ///
  /// We don't use the existing key directly so that different AppEngine versions
  /// using the same redis cache do not have collisions.
  String _genKey(String key) => 'server:$serverVersion:dart:${SdkManager.sdk.versionFull}+$key';

  @override
  Future<String> get(String key) async {
    String value;
    key = _genKey(key);
    if (!_isConnected()) {
      log.warning('$_logPrefix: no cache available when getting key $key');
    } else {
      final redis.Commands<String, String> commands =
          redisClient.asCommands<String, String>();
      // commands can return errors synchronously in timeout cases.
      try {
        value = await commands.get(key).timeout(cacheOperationTimeout,
            onTimeout: () async {
          log.warning('$_logPrefix: timeout on get operation for key $key');
          await redisClient?.disconnect();
          return null;
        });
      } catch (e) {
        log.warning('$_logPrefix: error on get operation for key $key: $e');
      }
    }
    return value;
  }

  @override
  Future<dynamic> remove(String key) async {
    key = _genKey(key);
    if (!_isConnected()) {
      log.warning('$_logPrefix: no cache available when removing key $key');
      return null;
    }

    final redis.Commands<String, String> commands =
        redisClient.asCommands<String, String>();
    // commands can sometimes return errors synchronously in timeout cases.
    try {
      return commands.del(key: key).timeout(cacheOperationTimeout,
          onTimeout: () async {
        log.warning('$_logPrefix: timeout on remove operation for key $key');
        await redisClient?.disconnect();
        return null;
      });
    } catch (e) {
      log.warning('$_logPrefix: error on remove operation for key $key: $e');
    }
  }

  @override
  Future<void> set(String key, String value, {Duration expiration}) async {
    key = _genKey(key);
    if (!_isConnected()) {
      log.warning('$_logPrefix: no cache available when setting key $key');
      return null;
    }

    final redis.Commands<String, String> commands =
        redisClient.asCommands<String, String>();
    // commands can sometimes return errors synchronously in timeout cases.
    try {
      return Future<void>.sync(() async {
        await commands.multi();
        unawaited(commands.set(key, value));
        if (expiration != null) {
          unawaited(commands.pexpire(key, expiration.inMilliseconds));
        }
        await commands.exec();
      }).timeout(cacheOperationTimeout, onTimeout: () {
        log.warning('$_logPrefix: timeout on set operation for key $key');
        redisClient?.disconnect();
      });
    } catch (e) {
      log.warning('$_logPrefix: error on set operation for key $key: $e');
    }
  }
}

/// An in-memory implementation of [ServerCache] which doesn't support
/// expiration of entries based on time.
class InMemoryCache implements ServerCache {
  /// Wrapping an internal cache with a maximum size of 512 entries.
  final Cache<String, String> _lru =
      MapCache<String, String>.lru(maximumSize: 512);

  @override
  Future<String> get(String key) async => _lru.get(key);

  @override
  Future<void> set(String key, String value, {Duration expiration}) async =>
      _lru.set(key, value);

  @override
  Future<void> remove(String key) async => _lru.invalidate(key);

  @override
  Future<void> shutdown() => Future<void>.value();
}

@ApiClass(name: 'dartservices', version: 'v1')
class CommonServer {
  final String sdkPath;
  final ProjectManager flutterWebManager;
  final ServerContainer container;
  final ServerCache cache;

  Compiler compiler;
  AnalysisServerWrapperManager analysisServerManager;

  CommonServer(
    this.sdkPath,
    this.flutterWebManager,
    this.container,
    this.cache,
  ) {
    hierarchicalLoggingEnabled = true;
    log.level = Level.ALL;
  }

  static const String sessionIdCookieName = 'dart-services-session-id';

  /// Returns the session ID cookie for the current request.
  ///
  /// Even if the original request does not have a cookie, the session cookie
  /// middleware should have created a new one.
  ///
  /// If the session cookie doesn't exist, then something went wrong, and
  /// an internal server error will be thrown.
  String get _sessionId {
    final cookies = CookieParser.fromHeader(context.requestHeaders);
    final sessionId = cookies.get(CommonServer.sessionIdCookieName)?.value;
    if (sessionId == null) {
      throw BadRequestError(
          'Missing session cookie; ensure that CORS is configured properly'
              ' and that the `session` endpoint is requested first');
    }
    return sessionId;
  }

  Future<void> init() async {
    analysisServerManager = AnalysisServerWrapperManager(sdkPath, flutterWebManager);
    compiler = Compiler(sdkPath, flutterWebManager);
  }

  Future<void> restart() async {
    log.warning('Restarting CommonServer');
    await shutdown();
    log.info('Analysis Servers shutdown');

    await init();

    log.warning('Restart complete');
  }

  Future<dynamic> shutdown() {
    return Future.wait(<Future<dynamic>>[
      analysisServerManager.dispose(),
      compiler.dispose(),
      Future<dynamic>.sync(cache.shutdown)
    ]);
  }

  @ApiMethod(
      method: 'POST',
      path: 'analyze',
      description:
          'Analyze the given Dart source code and return any resulting '
          'analysis errors or warnings.')
  Future<AnalysisResults> analyze(SourceRequest request) {
    return _analyze(request.source, projectId: _sessionId);
  }

  @ApiMethod(
      method: 'POST',
      path: 'compile',
      description: 'Compile the given Dart source code and return the '
          'resulting JavaScript; this uses the dart2js compiler.')
  Future<CompileResponse> compile(CompileRequest request) {
    return _compileDart2js(request.source,
        projectId: _sessionId,
        returnSourceMap: request.returnSourceMap ?? false);
  }

  @ApiMethod(
      method: 'POST',
      path: 'compileDDC',
      description: 'Compile the given Dart source code and return the '
          'resulting JavaScript; this uses the DDC compiler.')
  Future<CompileDDCResponse> compileDDC(CompileRequest request) {
    return _compileDDC(request.source, _sessionId);
  }

  @ApiMethod(
      method: 'POST',
      path: 'complete',
      description:
          'Get the valid code completion results for the given offset.')
  Future<CompleteResponse> complete(SourceRequest request) {
    
    
    if (request.offset == null) {
      throw BadRequestError('Missing parameter: \'offset\'');
    }

    return _complete(source: request.source, offset: request.offset, projectId: _sessionId);
  }

  @ApiMethod(
      method: 'POST',
      path: 'fixes',
      description: 'Get any quick fixes for the given source code location.')
  Future<FixesResponse> fixes(SourceRequest request) {
    if (request.offset == null) {
      throw BadRequestError('Missing parameter: \'offset\'');
    }

    return _fixes(source: request.source, offset: request.offset, projectId: _sessionId);
  }

  @ApiMethod(
      method: 'POST',
      path: 'assists',
      description: 'Get assists for the given source code location.')
  Future<AssistsResponse> assists(SourceRequest request) {
    if (request.offset == null) {
      throw BadRequestError('Missing parameter: \'offset\'');
    }

    return _assists(source: request.source, offset: request.offset, projectId: _sessionId);
  }

  @ApiMethod(
      method: 'POST',
      path: 'format',
      description: 'Format the given Dart source code and return the results. '
          'If an offset is supplied in the request, the new position for that '
          'offset in the formatted code will be returned.')
  Future<FormatResponse> format(SourceRequest request) {
    return _format(request.source, offset: request.offset, projectId: _sessionId);
  }

  @ApiMethod(
      method: 'POST',
      path: 'document',
      description: 'Return the relevant dartdoc information for the element at '
          'the given offset.')
  Future<DocumentResponse> document(SourceRequest request) {
    return _document(source: request.source, offset: request.offset, projectId: _sessionId);
  }

  @ApiMethod(
      method: 'GET',
      path: 'version',
      description: 'Return the current SDK version for DartServices.')
  Future<VersionResponse> version() =>
      Future<VersionResponse>.value(_version());

  Future<AnalysisServerWrapper> _getAnalysisServerWrapper(String projectId, {String source}) async {
    final wrapper = analysisServerManager.createWrapperIfNecessary(projectId);
    // TODO see if we can only call this when we need to instead of every time
    await wrapper.flutterWebManager.initFlutterWeb(source);
    await wrapper.init();
    return wrapper;
  }

  Future<AnalysisResults> _analyze(String source, {@required String projectId}) async {
    if (source == null) {
      throw BadRequestError('Missing parameter: \'source\'');
    }

    try {
      final Stopwatch watch = Stopwatch()..start();

      final analysisServer = await _getAnalysisServerWrapper(projectId, source: source);

      AnalysisResults results = await analysisServer.analyze(source);
      int lineCount = source.split('\n').length;
      int ms = watch.elapsedMilliseconds;
      log.info('PERF: Analyzed $lineCount lines of Dart in ${ms}ms.');
      return results;
    } catch (e, st) {
      log.severe('Error during analyze', e, st);
      await restart();
      rethrow;
    }
  }

  Future<CompileResponse> _compileDart2js(
    String source, {
    bool returnSourceMap = false,
    @required String projectId
  }) async {
    if (source == null) {
      throw BadRequestError('Missing parameter: \'source\'');
    }

    final sourceHash = _hashSource(source);
    final memCacheKey = '%%COMPILE:v0'
        ':returnSourceMap:$returnSourceMap:source:$sourceHash';

    final result = await checkCache(memCacheKey);
    if (result != null) {
      log.info('CACHE: Cache hit for compileDart2js');
      final resultObj = JsonDecoder().convert(result);
      return CompileResponse(
        resultObj['compiledJS'] as String,
        returnSourceMap ? resultObj['sourceMap'] as String : null,
      );
    }

    log.info('CACHE: MISS for compileDart2js');
    final watch = Stopwatch()..start();

    return compiler
        .compile(source, projectId: projectId, returnSourceMap: returnSourceMap)
        .then((CompilationResults results) {
      if (results.hasOutput) {
        final lineCount = source.split('\n').length;
        final outputSize = (results.compiledJS.length + 512) ~/ 1024;
        final ms = watch.elapsedMilliseconds;
        log.info('PERF: Compiled $lineCount lines of Dart into '
            '${outputSize}kb of JavaScript in ${ms}ms using dart2js.');
        final sourceMap = returnSourceMap ? results.sourceMap : null;

        final cachedResult = JsonEncoder().convert(<String, String>{
          'compiledJS': results.compiledJS,
          'sourceMap': sourceMap,
        });
        // Don't block on cache set.
        unawaited(setCache(memCacheKey, cachedResult));
        return CompileResponse(results.compiledJS, sourceMap);
      } else {
        final problems = results.problems;
        final errors = problems.map(_printCompileProblem).join('\n');
        throw BadRequestError(errors);
      }
    }).catchError((dynamic e, dynamic st) {
      if (e is! BadRequestError) {
        log.severe('Error during compile (dart2js): $e\n$st');
      }
      throw e;
    });
  }

  Future<CompileDDCResponse> _compileDDC(String source, String sessionId)
  async {
    if (source == null) {
      throw BadRequestError('Missing parameter: \'source\'');
    }

    final sourceHash = _hashSource(source);
    final memCacheKey = '%%COMPILE_DDC:v0:source:$sourceHash';

    final result = await checkCache(memCacheKey);

    if (result != null) {
      log.info('CACHE: Cache hit for compileDDC');
    }

    log.info('CACHE: MISS for compileDDC');
    Stopwatch watch = Stopwatch()..start();

    return compiler.compileDDC(source, projectId: sessionId).then(
            (DDCCompilationResults results) {
      if (results.hasOutput) {
        return CompileDDCResponse(results.entrypointUrl);
      } else {
        final problems = results.problems;
        final errors = problems.map(_printCompileProblem).join('\n');
        throw BadRequestError(errors);
      }
    }).catchError((dynamic e, dynamic st) {
      if (e is! BadRequestError) {
        log.severe('Error during compile (DDC): $e\n$st');
      }
      throw e;
    });
  }

  Future<DocumentResponse> _document({@required String source, @required int offset, @required String projectId}) async {
    if (source == null) {
      throw BadRequestError('Missing parameter: \'source\'');
    }
    if (offset == null) {
      throw BadRequestError('Missing parameter: \'offset\'');
    }

    Stopwatch watch = Stopwatch()..start();
    try {
      final analysisServer = await _getAnalysisServerWrapper(projectId, source: source);

      Map<String, String> docInfo =
          await analysisServer.dartdoc(source, offset);
      docInfo ??= <String, String>{};
      log.info('PERF: Computed dartdoc in ${watch.elapsedMilliseconds}ms.');
      return DocumentResponse(docInfo);
    } catch (e, st) {
      log.severe('Error during dartdoc', e, st);
      await restart();
      rethrow;
    }
  }

  VersionResponse _version() => VersionResponse(
      sdkVersion: SdkManager.sdk.version,
      sdkVersionFull: SdkManager.sdk.versionFull,
      runtimeVersion: vmVersion,
      servicesVersion: servicesVersion,
      appEngineVersion: container.version);

  Future<CompleteResponse> _complete({@required String source, @required int offset, @required String projectId}) async {
    if (source == null) {
      throw BadRequestError('Missing parameter: \'source\'');
    }
    if (offset == null) {
      throw BadRequestError('Missing parameter: \'offset\'');
    }

    Stopwatch watch = Stopwatch()..start();
    try {
      final analysisServer = await _getAnalysisServerWrapper(projectId, source: source);
      CompleteResponse response = await analysisServer.complete(source, offset);
      log.info('PERF: Computed completions in ${watch.elapsedMilliseconds}ms.');
      return response;
    } catch (e, st) {
      log.severe('Error during _complete', e, st);
      await restart();
      rethrow;
    }
  }

  Future<FixesResponse> _fixes({@required String source, @required int offset, @required String projectId}) async {
    if (source == null) {
      throw BadRequestError('Missing parameter: \'source\'');
    }
    if (offset == null) {
      throw BadRequestError('Missing parameter: \'offset\'');
    }

    Stopwatch watch = Stopwatch()..start();
    final analysisServer = await _getAnalysisServerWrapper(projectId, source: source);
    FixesResponse response = await analysisServer.getFixes(source, offset);
    log.info('PERF: Computed fixes in ${watch.elapsedMilliseconds}ms.');
    return response;
  }

  Future<AssistsResponse> _assists({@required String source, @required int offset, @required String projectId}) async {
    if (source == null) {
      throw BadRequestError('Missing parameter: \'source\'');
    }
    if (offset == null) {
      throw BadRequestError('Missing parameter: \'offset\'');
    }

    Stopwatch watch = Stopwatch()..start();
    final analysisServer = await _getAnalysisServerWrapper(projectId, source: source);
    var response = await analysisServer.getAssists(source, offset);
    log.info('PERF: Computed assists in ${watch.elapsedMilliseconds}ms.');
    return response;
  }

  Future<FormatResponse> _format(String source, {int offset, @required String projectId}) async {
    if (source == null) {
      throw BadRequestError('Missing parameter: \'source\'');
    }
    offset ??= 0;

    Stopwatch watch = Stopwatch()..start();

    final analysisServer = await _getAnalysisServerWrapper(projectId, source: source);
    FormatResponse response = await analysisServer.format(source, offset);
    log.info('PERF: Computed format in ${watch.elapsedMilliseconds}ms.');
    return response;
  }

  Future<String> checkCache(String query) => cache.get(query);

  Future<void> setCache(String query, String result) =>
      cache.set(query, result, expiration: _standardExpiration);

  Future<bool> _hasSessionFolder(String sessionId) async {
    final sessionDir =
        Directory('${Directory.current.path}/dartpadSessionCache/$sessionId');
    return sessionDir.exists();
  }
}

String _printCompileProblem(CompilationProblem problem) => problem.message;

String _hashSource(String str) {
  return sha1.convert(str.codeUnits).toString();
}
