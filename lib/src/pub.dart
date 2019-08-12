// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: implementation_imports

import 'package:analysis_server_lib/analysis_server_lib.dart';
import 'package:analyzer/analyzer.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/src/dart/scanner/reader.dart';
import 'package:analyzer/src/dart/scanner/scanner.dart';
import 'package:analyzer/src/string_source.dart';
import 'package:source_span/source_span.dart';

import 'common.dart';

Set<String> getAllImportsFor(String dartSource) {
  if (dartSource == null) return <String>{};

  Scanner scanner = Scanner(
    StringSource(dartSource, kMainDart),
    CharSequenceReader(dartSource),
    AnalysisErrorListener.NULL_LISTENER,
  );
  Token token = scanner.tokenize();
  Set<String> imports = <String>{};

  while (token.type != TokenType.EOF) {

    if (_isLibrary(token)) {
      token = _consumeSemi(token);
    } else if (_isImport(token)) {
      token = token.next;

      if (token.type == TokenType.STRING) {
        imports.add(stripMatchingQuotes(token.lexeme));
      }

      token = _consumeSemi(token);
    } else {
      break;
    }
  }

  return imports;
}

/// Returns an iterable of all the comments from [beginToken] to the end of the
/// file.
///
/// Comments are part of the normal stream, and need to be accessed via
/// [Token.precedingComments], so it's difficult to iterate over them without
/// this method.
Iterable<Token> allComments(Token beginToken) sync* {
  var currentToken = beginToken;
  while (!currentToken.isEof) {
    var currentComment = currentToken.precedingComments;
    while (currentComment != null) {
      yield currentComment;
      currentComment = currentComment.next;
    }

    currentToken = currentToken.next;
  }
}


Iterable<Token> getCommentsForNode(AstNode node, SourceFile sourceFile)  sync* {
  final line = sourceFile.getLine(node.offset);

  for (var comment in allComments(node.root.beginToken)) {
    final commentLine = sourceFile.getLine(comment.offset);
    var contentBeforeCommentInLine = sourceFile.getText(sourceFile.getOffset(sourceFile.getLine(comment.offset)), comment.offset);
    if (commentLine == line && comment.offset > node.offset) {
      yield comment;
    } else if (commentLine == line - 1 && contentBeforeCommentInLine.trim().isEmpty) {
      yield comment;
    }
  }
}

Iterable importInlineComment(Token importToken) sync* {
  var currentToken = importToken;
  var importCount = 0;
  while (importCount != 2 && !currentToken.isEof) {
    if (_isImport(currentToken)) {
      importCount += 1;
    }

    var currentComment = currentToken.precedingComments;
    while (currentComment != null) {
      yield currentComment;
      currentComment = currentComment.next;
    }
    currentToken = currentToken.next;
  }
  importCount = null;
}



Map<String, String> getAllPackagesFor(String dartSource) {
  if (dartSource == null) return <String, String>{};

  var unit = parseString(content: dartSource);
  var sourceFile = SourceFile.fromString(dartSource);
  Map<String, String> packages = <String, String>{};
  unit.unit.directives.whereType<ImportDirective>().forEach((import){
    var comments = getCommentsForNode(import, sourceFile);
    String comment;
    if (comments.isNotEmpty){
      comment = comments.length == 2 ? comments.last.toString() : comments.single.toString();
    }
    if (!import.uri.toString().contains('dart:')) {
      packages[getPackageNameFromImport(import.uri.stringValue)] = getVersionFromComment(comment);
    }
  });

  return packages;
}


String getVersionFromComment([String comment = '']) {
  if (comment == null) return 'any';
  var verison = comment.replaceAll('//', '').trim().toString();
  return verison.isNotEmpty ? verison : 'any';
}

String getPackageNameFromImport(String import) {
  String packageName = import;

  if (packageName.startsWith('package:')){
    packageName = packageName.substring(8);
  }

  int index = packageName.indexOf('/');
  packageName =  index == -1 ? packageName : packageName.substring(0, index);

  packageName.replaceAll('..', '');

  return packageName;
}

/// Return the list of packages that are imported from the given imports. These
/// packages are sanitized defensively.
Set<String> filterSafePackagesFromImports(Set<String> allImports) {
  return Set<String>.from(allImports.where((String import) {
    return import.startsWith('package:');
  }).map((String import) {
    return import.substring(8);
  }).map((String import) {
    int index = import.indexOf('/');
    return index == -1 ? import : import.substring(0, index);
  }).map((String import) {
    return import.replaceAll('..', '');
  }).where((String import) {
    return import.isNotEmpty;
  }));
}

bool _isLibrary(Token token) {
  return token.isKeyword && token.lexeme == 'library';
}

bool _isImport(Token token) {
  return token.isKeyword && token.lexeme == 'import';
}

Token _consumeSemi(Token token) {
  while (token.type != TokenType.SEMICOLON) {
    if (token.type == TokenType.EOF) return token;
    token = token.next;
  }

  // Skip past the semi-colon.
  token = token.next;

  return token;
}
