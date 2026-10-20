import 'dart:io';

/// Platform environment lookup backed by `dart:io`.
String? platformEnv(String name) => Platform.environment[name];
