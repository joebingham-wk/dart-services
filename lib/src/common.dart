// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library services.common;

import 'dart:io';

import 'sdk_manager.dart';

const kMainDart = 'web/main.dart';

const sampleCode = '''
void main() {
  print("hello");
}
''';

const sampleCodeWeb = """
import 'dart:html';

void main() {
  print("hello");
  querySelector('#foo').text = 'bar';
}
""";

const sampleCodeMultiFoo = """
import 'bar.dart';

void main() {
  print(bar());
}
""";

const sampleCodeMultiBar = '''
bar() {
  return 4;
}
''';

const sampleCodeAsync = """
import 'dart:html';

main() async {
  print("hello");
  querySelector('#foo').text = 'bar';
  var foo = await HttpRequest.getString('http://www.google.com');
  print(foo);
}
""";

const sampleCodeError = '''
void main() {
  print("hello")
}
''';

const sampleCodeErrors = '''
void main() {
  print1("hello");
  print2("hello");
  print3("hello");
}
''';

const sampleStrongError = """
void main() {
  foo('whoops');
}

void foo(int i) {
  print(i);
}
""";

const sampleDart2OK = """
class Foo {
  String toString() => 'hello';
}

void main(List<String> argv) {
  print (Foo());
}
""";

const sampleDart2Error = '''
class Foo {
  final bool isAlwaysNull;
  Foo(this.isAlwaysNull) {}
}

void main(List<String> argv) {
  var x = new Foo(null);
  var y = 1;
  y = x;
}
''';

class Lines {
  final List<int> _starts = <int>[];

  Lines(String source) {
    List<int> units = source.codeUnits;
    for (int i = 0; i < units.length; i++) {
      if (units[i] == 10) _starts.add(i);
    }
  }

  /// Return the 0-based line number.
  int getLineForOffset(int offset) {
    assert(offset != null);
    for (int i = 0; i < _starts.length; i++) {
      if (offset <= _starts[i]) return i;
    }
    return _starts.length;
  }
}

/// Returns the version of the current Dart runtime.
///
/// The returned `String` is formatted as the [semver](http://semver.org) version
/// string of the current Dart runtime, possibly followed by whitespace and other
/// version and build details.
String get vmVersion => Platform.version;

/// If [str] has leading and trailing quotes, remove them.
String stripMatchingQuotes(String str) {
  if (str.length <= 1) return str;

  if (str.startsWith("'") && str.endsWith("'")) {
    str = str.substring(1, str.length - 1);
  } else if (str.startsWith('"') && str.endsWith('"')) {
    str = str.substring(1, str.length - 1);
  }
  return str;
}

String get sdkPath => SdkManager.sdk.sdkPath;
