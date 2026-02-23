const fs = require('fs');
const path = require('path');

function processDirectory(dirPath) {
    const entries = fs.readdirSync(dirPath, { withFileTypes: true });

    for (const entry of entries) {
        const fullPath = path.join(dirPath, entry.name);

        if (entry.isDirectory()) {
            processDirectory(fullPath);
        } else if (entry.isFile() && fullPath.endsWith('.dart')) {
            let content = fs.readFileSync(fullPath, 'utf8');

            let modified = false;

            // Replace print( with debugPrint(
            if (content.includes('print(')) {
                content = content.replace(/([^a-zA-Z0-9_])print\(/g, '$1debugPrint(');

                // Ensure standard foundation import exists if we added debugPrint
                if (!content.includes("import 'package:flutter/foundation.dart';")) {
                    content = "import 'package:flutter/foundation.dart';\n" + content;
                }
                modified = true;
            }

            // Replace .withOpacity(x) with .withValues(alpha: x)
            const opacityRegex = /\.withOpacity\(([^)]+)\)/g;
            if (opacityRegex.test(content)) {
                content = content.replace(opacityRegex, '.withValues(alpha: $1)');
                modified = true;
            }

            // Fix specific unintended html bracket issue in app_config.dart
            if (fullPath.includes('app_config.dart') && content.includes('<YOUR_LARAVEL_URL_HERE>')) {
                content = content.replace('<YOUR_LARAVEL_URL_HERE>', 'YOUR_LARAVEL_URL_HERE');
                modified = true;
            }

            if (modified) {
                fs.writeFileSync(fullPath, content, 'utf8');
                console.log(`Updated: ${fullPath}`);
            }
        }
    }
}

const libPath = path.join(__dirname, 'lib');
processDirectory(libPath);
console.log('Done.');
