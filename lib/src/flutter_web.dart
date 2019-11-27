// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:dart_services/src/pub.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import 'sdk_manager.dart';

Logger _logger = Logger('flutter_web');

class ProjectManager {
  final String sdkPath;
  final Directory _projectsDirectory;

  final Map<String, Project> _projectsByName = {};

  ProjectManager(this.sdkPath, {String projectsDirectory})
    : _projectsDirectory = projectsDirectory != null ? Directory(projectsDirectory).absolute : Directory.systemTemp.createTempSync('dartpad');

  Project _createProject(String projectId) {
    final projectDirectory = Directory(path.join(_projectsDirectory.path, projectId))
        ..createSync(recursive: true);
    return _projectsByName[projectId] = Project(sdkPath, projectDirectory, projectId);
  }

  Project createProjectWithoutId() {
    final id = Uuid().v4();
    _createProject(id);

    return getProject(id);
  }

  Project createProjectIfNecessary(String projectId) =>
      _projectsByName[projectId] ??= _createProject(projectId);

  Project getProject(String projectId) => _projectsByName[projectId];
}

/// Handle provisioning package:flutter_web and related work.
class Project {
  final String sdkPath;
  final String id;

  Directory _projectDirectory;

  Project(this.sdkPath, this._projectDirectory, this.id) {
    _init();
  }

  void dispose() {
    _projectDirectory.deleteSync(recursive: true);
  }

  Directory get projectDirectory => _projectDirectory;

  Directory get outputDirectory => Directory(path.join(_projectDirectory.path, 'build'));

  String get packagesFilePath => path.join(projectDirectory.path, '.packages');

  void _init() {
    // create a pubspec.yaml file
    String pubspec = createPubspec(false);
    File(path.join(_projectDirectory.path, 'pubspec.yaml'))
        .writeAsStringSync(pubspec);

    // create a .packages file
    final String packagesFileContents = '''
$_samplePackageName:lib/
''';
    File(path.join(_projectDirectory.path, '.packages'))
        .writeAsStringSync(packagesFileContents);

    // and create a lib/ folder for completeness
    Directory(path.join(_projectDirectory.path, 'lib')).createSync();
  }

  Future<void> warmup() async {
    try {
      await initFlutterWeb();
    } catch (e, s) {
      _logger.warning('Error initializing flutter web', e, s);
    }
  }

  Future<void> initFlutterWeb([String source]) async {
    Map<String, String> packages;

    if (source != null){
      packages = getAllPackagesFor(source);
    }

    _logger.info('creating flutter web pubspec');
    String pubspec = createPubspec(true, packages);

    await File(path.join(_projectDirectory.path, 'pubspec.yaml'))
        .writeAsString(pubspec);

    await _runPubGet();
  }

  String get summaryFilePath {
    return path.join(_projectDirectory.path, 'flutter_web.sum');
  }

  bool usesFlutterWeb(Set<String> imports) {
    return true;
  }

  bool hasUnsupportedImport(Set<String> imports) {
    return getUnsupportedImport(imports) != null;
  }

  String getUnsupportedImport(Set<String> imports) {
    // TODO(devoncarew): Should we support a white-listed set of package:
    // imports?

    for (String import in imports) {
      // All dart: imports are ok;
      if (import.startsWith('dart:')) {
        continue;
      }

      // Currently we only allow flutter web imports.
      if (import.startsWith('package:')) {
        continue;
      }

      // Don't allow file imports.
      return import;
    }

    return null;
  }

  Future<void> _runPubGet() async {
    _logger.info('running pub get (${_projectDirectory.path})');

    ProcessResult result = await Process.run(
      path.join(sdkPath, 'bin', 'pub'),
      <String>['get', '--no-precompile'],
      workingDirectory: _projectDirectory.path,
    );

    _logger.info('${result.stdout}'.trim());

    if (result.exitCode != 0) {
      _logger.warning('pub get failed: ${result.exitCode}');
      _logger.warning(result.stderr);

      throw 'pub get failed: ${result.exitCode}';
    }
  }

  static const String _samplePackageName = 'dartpad_sample';

  // Last collected on 8/12/19
  static const List<String> workivaHostedPubPackages = [
    "doc_plat_client",
    "graph_ui",
    "home",
    "web_skin_dart",
    "cerebral_ui",
    "w_translate",
    "dart_permissions_editor",
    "graph_api",
    "audit",
    "w_viewer",
    "copy_ui",
    "sa_tools_toolbox",
    "w_comments",
    "w_annotations_api",
    "xbrl_module",
    "w_filing",
    "w_attachments",
    "wdesk_login",
    "blob_storage",
    "w_router",
    "w_graph_client",
    "w_attachments_client",
    "xbrl_orchestrator_api",
    "undo_redo",
    "w_input_validation",
    "react_tracing",
    "w_session",
    "drawing",
    "w_oauth2",
    "user_analytics",
    "wdesk_sdk",
    "w_link_properties_ui",
    "wContent_frugal",
    "data_modeler",
    "comments_frugal",
    "w_sox",
    "w_history",
    "focus",
    "workflow_client",
    "review_bar",
    "app_intelligence",
    "w_table",
    "design_system",
    "storybook",
    "licensing_frugal",
    "w_clipboard",
    "speedparser",
    "web_skin",
    "filing_orchestrator_api",
    "wf_js_document_viewer",
    "workflow_frugal",
    "history_frugal",
    "admin_client",
    "wdesk_sdk_builders",
    "workspaces_components",
    "tasker",
    "permissions_editor",
    "markup",
    "w_editor_dev_tools",
    "w_user_color_module",
    "w_outline",
    "ale_frugal",
    "visjs",
    "w_dashboard",
    "graph_form_api",
    "workflow_catalog_assets",
    "w_filing_api",
    "sdlc_analytics",
    "messaging_sdk",
    "xbrl_importer_api",
    "w_project",
    "docmodel_frugal",
    "dataset_service_api",
    "audit_api",
    "fastpath_api",
    "find_ui",
    "w_virtual_components",
    "snapshot",
    "bigsky_rest_files",
    "linking_sdk",
    "home_frugal",
    "xbrl_config_api",
    "workspaces_api",
    "dataset_service_ui",
    "wdata_ui_utils",
    "admin_frugal",
    "linking_frugal",
    "workspaces_frugal",
    "rcal_api",
    "xbrl2_server_api",
    "w_test_tools",
    "licensing_api",
    "w_dashboard_frugal",
    "frugal",
    "forms_definitions_experience",
    "sa_tools_data_selections",
    "copy_frugal",
    "file_services_sdk",
    "grc_services_frugal",
    "commitlog_frugal"
    "proofread_frugal",
    "highcharts",
    "over_react_format",
    "web_skin_docs",
    "thrift",
    "w_webdriver_utils",
    "sa_tools_rollforward",
    "w_context_menu",
    "workiva_scripts",
    "vessel",
    "mock_messaging_service_sdk",
    "w_office_online_frame",
    "tasker_frugal",
    "tour",
    "sockjs_client",
    "mockito_compat",
    "wuri_sdk",
    "support_viewer_frugal",
    "skaardb",
    "text_doc_client",
    "charts",
    "datatables",
    "w_editor_properties",
    "key_binder",
    "iam_landing_page",
    "designated_driver",
    "truss",
    "basictracer_dart",
    "dart_version",
    "test_invoker",
    "semver_audit",
    "eva_admin_frugal",
    "bigsky_webdriver_utils",
    "abide",
    "bender",
    "eva_frugal",
    "sw_toolbox_dart",
    "contract_creator",
    "dart_medic",
    "admiral_ui",
    "mms_example_idl",
    "idm_frugal",
    "unscripted",
    "browser_storage",
    "notification_services_frugal",
    "content_management_api_frugal",
    "standards_api",
    "opentracing_dart",
    "data_platform_api_frugal",
    "font_face_observer",
    "content_search_frugal",
    "fs_viewer_api",
    "toolbars",
    "lux_bindings",
    "doc_client",
    "content_search_service_frugal",
    "support_api_frugal",
    "lux_editor",
    "w_chart",
    "xbrl2_validation_api",
    "w_crdt",
    "resource_index_frugal",
    "xbrl_translator_api",
    "notifications_service_frugal",
    "announcement_feed",
    "wdata",
    "filing_api",
    "wdesk_examples",
    "sauce_unit_test_runner",
    "search_client",
    "infer_client",
    "ixbrl_importer_api",
    "webdwiver",
    "comments_and_tasks",
    "wContent",
    "color",
    "licensing_admin_dart",
    "graph_printing_orchestrator_sdk",
    "licensing_api_dart",
    "cerberus_dart",
    "platform_detect",
    "xbrl2_server_frontend",
    "docsserver_dart",
    "role_manager",
    "w_common",
    "shapes",
    "workspaces",
    "wlayout",
    "dev_portal",
    "dev_console_shell",
    "rcal_client",
    "wSoxDashboards",
    "certifier",
    "wchart"
  ];

  // TODO: Add support for git overrides
  static String generateDependency(String package, [String version = 'any']) {
    if (workivaHostedPubPackages.contains(package)){
      return '''
  $package:
    hosted:
      name: $package
      url: https://pub.workiva.org
    version: $version
''';
    }
    return '  $package: $version\n';
  }

  static String createPubspec(bool includeFlutterWeb, [Map<String, String> packages]) {
    String content = '''
name: $_samplePackageName
''';

    if (packages?.isNotEmpty != null){
      content += '\ndependencies:\n';
      packages.forEach((package, version){
        content += generateDependency(package, version);
      });
    }
    if (includeFlutterWeb) {
      content += '''
dev_dependencies:
  build_runner: ^1.0.0
  build_web_compilers: ^2.0.0
''';
    }
    return content;
  }
}
