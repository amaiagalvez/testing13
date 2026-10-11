<?php

/**
 * Chisel Markers Integrity Test
 *
 * Validates that all chisel markers have matching
 * end-chisel markers and are properly structured.
 *
 * Run from workspace root (l13/):
 *   docker compose -f projects/demo13/docker-compose.yml run --rm --no-deps -e XDEBUG_MODE=off \
      -v "$(pwd)/testing13:/testing13" -w /app-docker \
      --entrypoint php laravel13 /testing13/tests/chisel-integrity-test.php
 *
 * From projects/demo13/, use -f docker-compose.yml and mount
 * "$(pwd)/../../testing13:/testing13" instead.
 */

// Detect base path: if /app-docker exists (running in container), use it.
// Otherwise use relative path from this script.
if (is_dir('/app-docker')) {
    $basePath = '/app-docker';
} else {
    $basePath = __DIR__.'/../../projects/demo13';
}

$sourceFiles = new RecursiveCallbackFilterIterator(
    new RecursiveDirectoryIterator($basePath, RecursiveDirectoryIterator::SKIP_DOTS),
    static function (SplFileInfo $file) use ($basePath): bool {
        return ! ($file->isDir()
            && $file->getPath() === $basePath
            && in_array($file->getFilename(), ['.git', 'dc-data', 'node_modules', 'storage', 'vendor'], true));
    }
);

$phpFiles = new RecursiveIteratorIterator(
    $sourceFiles,
    RecursiveIteratorIterator::LEAVES_ONLY
);

$bladeFiles = new RecursiveIteratorIterator(
    new RecursiveDirectoryIterator($basePath.'/resources/views', RecursiveDirectoryIterator::SKIP_DOTS),
    RecursiveIteratorIterator::LEAVES_ONLY
);

$allFiles = [];
foreach ($phpFiles as $file) {
    if ($file->isFile() && $file->getExtension() === 'php') {
        $allFiles[] = $file->getPathname();
    }
}
foreach ($bladeFiles as $file) {
    if ($file->isFile() && $file->getExtension() === 'blade.php') {
        $allFiles[] = $file->getPathname();
    }
}

$errors = [];
$warnings = [];
$markerStack = [];

foreach ($allFiles as $filePath) {
    $content = file_get_contents($filePath);
    if ($content === false) {
        continue;
    }

    $relativePath = str_replace($basePath.'/', '', $filePath);
    $lines = explode("\n", $content);
    $inBladeComment = false;

    foreach ($lines as $lineNum => $line) {
        $lineNum++; // 1-based

        // Detect blade comment start/end
        if (strpos($line, '{{--') !== false) {
            $inBladeComment = true;
        }
        if (strpos($line, '--}}') !== false) {
            $inBladeComment = false;
        }

        // Match @chisel-<feature> markers
        if (preg_match('/\/\*\s*@chisel-([a-z0-9-]+)\s*\*\//', $line, $matches)) {
            $feature = $matches[1];
            $markerStack[] = [
                'feature' => $feature,
                'file' => $relativePath,
                'line' => $lineNum,
                'type' => $inBladeComment ? 'blade' : 'php',
            ];
        }

        // Match @end-chisel-<feature> markers
        if (preg_match('/\/\*\s*@end-chisel-([a-z0-9-]+)\s*\*\//', $line, $matches)) {
            $feature = $matches[1];

            // Find matching opening marker
            $found = false;
            for ($i = count($markerStack) - 1; $i >= 0; $i--) {
                if ($markerStack[$i]['feature'] === $feature) {
                    $found = true;
                    array_splice($markerStack, $i, 1);
                    break;
                }
            }

            if (! $found) {
                $errors[] = "[$relativePath:$lineNum] Unmatched @end-chisel-$feature (no opening marker)";
            }
        }
    }
}

// Check for unclosed markers
foreach ($markerStack as $marker) {
    $errors[] = "[{$marker['file']}:{$marker['line']}] Unclosed @chisel-{$marker['feature']} (no closing marker)";
}

// Summary
echo "Chisel Markers Integrity Check\n";
echo "==============================\n";
echo "Base path: $basePath\n";
echo 'Files scanned: '.count($allFiles)."\n";
echo 'Errors: '.count($errors)."\n";
echo 'Warnings: '.count($warnings)."\n\n";

if (! empty($errors)) {
    echo "ERRORS:\n";
    foreach ($errors as $error) {
        echo "  - $error\n";
    }
    echo "\n";
    exit(1);
}

if (! empty($warnings)) {
    echo "WARNINGS:\n";
    foreach ($warnings as $warning) {
        echo "  - $warning\n";
    }
    echo "\n";
}

echo "✓ All chisel markers are properly paired.\n";
exit(0);
