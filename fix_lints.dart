import 'dart:io';

void main() async {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    print('lib directory not found');
    return;
  }

  // Find all .dart files recursively
  final files = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  for (final file in files) {
    String content = await file.readAsString();
    bool modified = false;

    // 1. avoid_print -> replace 'print(' with 'debugPrint('
    final printRegex = RegExp(r'(?<![a-zA-Z0-9_])print\(');
    if (printRegex.hasMatch(content)) {
      content = content.replaceAll(printRegex, 'debugPrint(');

      // Add foundation.dart if missing and requires debugPrint
      if (!content.contains("package:flutter/foundation.dart") &&
          !content.contains("package:flutter/material.dart") &&
          !content.contains("package:flutter/widgets.dart")) {
        content = "import 'package:flutter/foundation.dart';\n$content";
      }
      modified = true;
    }

    // 2. withOpacity(val) -> withValues(alpha: val)
    final opacityRegex = RegExp(r'\.withOpacity\(([^)]+)\)');
    if (opacityRegex.hasMatch(content)) {
      content = content.replaceAllMapped(opacityRegex, (match) {
        return '.withValues(alpha: ${match.group(1)})';
      });
      modified = true;
    }

    // 3. MaterialStateProperty -> WidgetStateProperty
    if (content.contains('MaterialStateProperty')) {
      content =
          content.replaceAll('MaterialStateProperty', 'WidgetStateProperty');
      modified = true;
    }

    // 4. MaterialState -> WidgetState
    if (content.contains('MaterialState.')) {
      content = content.replaceAll('MaterialState.', 'WidgetState.');
      modified = true;
    }

    // 5. Unintended HTML bracket error in app_config.dart
    if (file.path.contains('app_config.dart') &&
        content.contains('<YOUR_LARAVEL_URL_HERE>')) {
      content = content.replaceAll(
          '<YOUR_LARAVEL_URL_HERE>', 'YOUR_LARAVEL_URL_HERE');
      modified = true;
    }

    if (modified) {
      await file.writeAsString(content);
      print('Fixed: ${file.path}');
    }
  }

  print('Done applying custom fixes!');
}
