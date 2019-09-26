
import 'package:rpc/common.dart';

@ApiClass(name: 'staticfileserver', version: 'v1')
class StaticFileServer {



  @ApiMethod(method: 'GET', path: 'getFolder/{sessionId}/{path}')
  Future<Test> getFolder(/*SessionId*/ String sessionId, String path) {

    return Future.value(Test('The session ID is: ${sessionId}; The Path is: '
        '${path}'));
  }

}

class Test {
  String peanutButter;

  Test(this.peanutButter);
}