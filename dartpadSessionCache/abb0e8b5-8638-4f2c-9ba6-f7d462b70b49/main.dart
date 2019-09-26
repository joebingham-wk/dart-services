import 'dart:html';

import 'package:react/react_dom.dart' as react_dom;
import 'package:web_skin_dart/ui_components.dart';
import 'package:web_skin_dart/ui_core.dart';
import 'package:web_skin/web_skin.dart';


void main() {
  setClientConfiguration();
  print('hello');
  react_dom.render(Block()((Button()..skin = ButtonSkin.ALTERNATE)('Hello')), querySelector('.main'));
}
