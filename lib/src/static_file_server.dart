
import 'package:rpc/common.dart';

@ApiClass(name: 'staticfileserver', version: 'v1')
class StaticFileServer {

  @ApiMethod(method: 'GET', path: 'getFolder/{sessionId}/{path}')
  Future<SessionFolder> getFolder(/*SessionId*/ String sessionId, String path) {

    return Future.value(SessionFolder('The session ID is: ${sessionId}; The '
        'Path '
        'is: '
        '${path}'));
  }

}

class SessionFolder {
  String path;

  SessionFolder(this.path);
}