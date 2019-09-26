
import 'dart:io';

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
    final outputFile = File(p.canonicalize(outputFolderPath + p.separator + path));

    if (!p.isWithin(outputFolderPath, outputFile.path)) {
      return Response.forbidden('"$path" is outside of output folder');
    }

    if (!outputFile.existsSync()) {
      return Response.notFound('"$path" not found within output files');
    }

    return Response.ok(await outputFile.readAsString());
  }
}
