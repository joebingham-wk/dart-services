
import 'dart:io';

import 'package:mime/mime.dart';
import 'package:shelf/shelf.dart';
import 'package:path/path.dart' as p;

import 'flutter_web.dart';

class StaticFileServer {
  final ProjectManager _projectManager;

  StaticFileServer(this._projectManager);
  
  Future<Response> getCompiledOutput(String projectId, String path) async {
    final project = _projectManager.getProject(projectId);
    if (project == null) {
      return Response.notFound('project "$projectId" not found');
    }

    final outputFolderPath = p.canonicalize(project.outputDirectory.path);
    // Use `p.separator` instead of `p.join` so that `path` isn't treated as absolute
    // if it has a leading slash.
    var outputFile = File(p.canonicalize(outputFolderPath + p.separator + path));

    if (!p.isWithin(outputFolderPath, outputFile.path)) {
      return Response.forbidden('"$path" is outside of output folder');
    }

    var outputFileExists = outputFile.existsSync();
    if (!outputFileExists && p.extension(outputFile.path) == '.bootstrap') {
      outputFile = File('${outputFile.path}.js');
      outputFileExists = outputFile.existsSync();
    }
    if (!outputFileExists) {
      return Response.notFound('"$path" not found within output files');
    }

    return Response.ok((await outputFile.readAsString())
        // main.bootstrap.dart.js
        .replaceAll(
          r'window.$dartLoader.rootDirectories.push(window.location.origin + baseUrl);',
          r'window.$dartLoader.rootDirectories.push(baseUrl);'
        )
        // main.bootstrap.dart.js
        .replaceAll(
          r"var src = window.location.origin + '/' + modulePath + '.js';",
          r"var src = baseUrl + '/' + modulePath + '.js';"
        )
        // main.dart.js
        // main.bootstrap.dart.js
        // more?
        .replaceAll(
          r'&& el[0].getAttribute' '\n'r'    ("href").startsWith("/")',
          '',
        )
        // TODO is this needed?
        // main.dart.js
        .replaceAll(
          r'var mainUri = _currentDirectory + "main.dart.bootstrap";',
          r'var mainUri = "main.dart.bootstrap";'
        )
        , headers: {'content-type': lookupMimeType(outputFile.path)});
  }
}
