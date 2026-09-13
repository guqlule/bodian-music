import 'dart:io';
import 'dart:convert';

void main() {
  final sourceDir = Directory('E:\\lx-music-flutter\\lx-music-source-main');
  final jsFiles = sourceDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.js'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  stdout.writeln('========================================');
  stdout.writeln('  LX Music Source Scripts Analysis');
  stdout.writeln('  Total: ${jsFiles.length} scripts');
  stdout.writeln('========================================');
  stdout.writeln('');

  final results = <Map<String, dynamic>>[];

  for (final file in jsFiles) {
    final rel = file.path.replaceFirst(sourceDir.path + Platform.pathSeparator, '');
    final r = analyzeScript(rel, file);
    results.add(r);
    printResult(r);
  }
  printSummary(results);
}

Map<String, dynamic> analyzeScript(String path, File file) {
  final content = file.readAsStringSync();
  final warnings = <String>[];
  final errors = <String>[];

  // Metadata
  final commentMatch = RegExp(r'^/\*[\s\S]+?\*/').firstMatch(content);
  String name = 'unknown';
  String version = 'unknown';
  String author = 'unknown';
  if (commentMatch != null) {
    final block = commentMatch.group(0)!;
    name = RegExp(r'@name\s+(.+)').firstMatch(block)?.group(1)?.trim() ?? name;
    version = RegExp(r'@version\s+(.+)').firstMatch(block)?.group(1)?.trim() ?? version;
    author = RegExp(r'@author\s+(.+)').firstMatch(block)?.group(1)?.trim() ?? author;
  } else {
    warnings.add('No block comment metadata');
  }

  // lx.on('request') OR on(EVENT_NAMES.request, ...) OR on(alias.request, ...)
  // Also detect aliased patterns like: let{EVENT_NAMES:n,request:b,on,send:y}=globalThis.lx
  // Then: on(n.request, ...) and y(n.inited, ...)
  final hasRequestHandler = content.contains(RegExp(
    r"""(?:lx\.on\s*\(\s*['"]request['"]|on\s*\(\s*EVENT_NAMES\.request|on\s*\(\s*\w+\.request\b)""",
    caseSensitive: false,
  ));

  // lx.send('inited') OR send(EVENT_NAMES.inited, ...) OR send(alias.inited, ...) OR alias(alias2.inited, ...)
  final hasInitSend = content.contains(RegExp(
    r"""(?:lx\.send\s*\(\s*['"](?:inited|init)['"]|send\s*\(\s*EVENT_NAMES\.inited|send\s*\(\s*\w+\.inited|=\s*send\b)""",
    caseSensitive: false,
  )) && content.contains(RegExp(
    r"""(?:inited|init)""",
    caseSensitive: false,
  ));

  // Source IDs from init data sources:{...}
  final sourceIds = <String>{};
  // Pattern 1: send(EVENT_NAMES.inited, {...sources: {kw: {...}, ...}...})
  // Pattern 2: send('inited', {...sources: {kw: {...}, ...}...})
  // Pattern 3: lx.send('inited', {...sources: {kw: {...}, ...}...})
  // Extract the sources block from the send call
  for (final m in RegExp(
    r"""send\s*\([^)]*sources\s*:\s*\{([^}]*(?:\{[^}]*\}[^}]*)*)\}""",
    caseSensitive: false,
  ).allMatches(content)) {
    final block = m.group(1)!;
    for (final km in RegExp(r"""['"]?(\w+)['"]?\s*:""").allMatches(block)) {
      final key = km.group(1)!;
      if (!{'name', 'type', 'actions', 'qualitys', 'quality', 'url'}.contains(key)) {
        sourceIds.add(key);
      }
    }
  }
  // Fallback: extract common source IDs from anywhere in file
  for (final m in RegExp(r"""['"]?(kw|wy|tx|kg|mg|bd|kugou|kuwo|yc)['"]?""", caseSensitive: false).allMatches(content)) {
    final src = m.group(1)!.toLowerCase();
    sourceIds.add(src);
  }

  // Actions
  final actions = <String>{};
  for (final act in ['musicUrl', 'lyric', 'pic', 'search', 'musicInfo']) {
    if (content.contains("'$act'") || content.contains('"$act"')) {
      actions.add(act);
    }
  }

  // Checks
  if (hasRequestHandler && !actions.contains('musicUrl')) {
    warnings.add('Request handler missing musicUrl action');
  }
  if (hasRequestHandler && sourceIds.isEmpty) {
    warnings.add('Has handler but no source IDs found');
  }

  // Braces balance
  int braceCount = 0;
  for (final ch in content.runes) {
    if (ch == 0x7B) braceCount++; // {
    if (ch == 0x7D) braceCount--; // }
  }
  if (braceCount != 0) errors.add('Braces unbalanced (diff=${braceCount.abs()})');

  int parenCount = 0;
  for (final ch in content.runes) {
    if (ch == 0x28) parenCount++; // (
    if (ch == 0x29) parenCount--; // )
  }
  if (parenCount != 0) errors.add('Parens unbalanced (diff=${parenCount.abs()})');

  int bracketCount = 0;
  for (final ch in content.runes) {
    if (ch == 0x5B) bracketCount++; // [
    if (ch == 0x5D) bracketCount--; // ]
  }
  if (bracketCount != 0) errors.add('Brackets unbalanced (diff=${bracketCount.abs()})');

  if (content.contains('window.') && !content.contains('typeof window')) {
    warnings.add('Uses window.* (may not work on mobile)');
  }
  if (content.contains('document.') && !content.contains('typeof document')) {
    warnings.add('Uses document.* (may not work on mobile)');
  }

  return {
    'path': path,
    'name': name,
    'version': version,
    'author': author,
    'handler': hasRequestHandler,
    'init': hasInitSend,
    'sources': sourceIds,
    'actions': actions.toList(),
    'warnings': warnings,
    'errors': errors,
    'size': content.length,
  };
}

void printResult(Map<String, dynamic> r) {
  final errs = r['errors'] as List;
  final warns = r['warnings'] as List;
  final icon = errs.isNotEmpty ? 'X' : (warns.isNotEmpty ? '!' : 'V');
  stdout.writeln('[$icon] ${r['path']}');
  stdout.writeln('    name=${r['name']}  ver=${r['version']}  author=${r['author']}');
  stdout.writeln('    handler=${r['handler'] ? "YES" : "NO"}  init=${r['init'] ? "YES" : "NO"}  size=${((r['size'] as int) / 1024).round()}KB');
  final srcs = (r['sources'] as Set).toList();
  if (srcs.isNotEmpty) stdout.writeln('    sources: ${srcs.join(", ")}');
  final acts = r['actions'] as List;
  if (acts.isNotEmpty) stdout.writeln('    actions: ${acts.join(", ")}');
  for (final w in warns) stdout.writeln('    WARN: $w');
  for (final e in errs) stdout.writeln('    ERROR: $e');
  stdout.writeln('');
}

void printSummary(List<Map<String, dynamic>> results) {
  stdout.writeln('========================================');
  stdout.writeln('  Summary');
  stdout.writeln('========================================');
  final passed = results.where((r) => r['errors'].isEmpty && r['handler'] == true && r['init'] == true).length;
  final withHandler = results.where((r) => r['handler'] == true).length;
  final withInit = results.where((r) => r['init'] == true).length;
  final allSources = <String>{};
  final allActions = <String>{};
  for (final r in results) {
    for (final s in r['sources'] is Set ? r['sources'] as Set : (r['sources'] as List).toSet()) allSources.add(s.toString());
    for (final a in r['actions'] as List) allActions.add(a.toString());
  }
  stdout.writeln('  Total: ${results.length}');
  stdout.writeln('  Passed (handler+init+no error): $passed / ${results.length}');
  stdout.writeln('  Has request handler: $withHandler / ${results.length}');
  stdout.writeln('  Has init send: $withInit / ${results.length}');
  stdout.writeln('  Source IDs found: ${allSources.join(", ")}');
  stdout.writeln('  Actions found: ${allActions.join(", ")}');

  final failed = results.where((r) => r['errors'].isNotEmpty || r['handler'] != true || r['init'] != true).toList();
  if (failed.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('  Issues:');
    for (final r in failed) {
      final issues = <String>[];
      if (r['handler'] != true) issues.add('no handler');
      if (r['init'] != true) issues.add('no init');
      for (final e in r['errors'] as List) issues.add('ERR: $e');
      for (final w in r['warnings'] as List) issues.add('WARN: $w');
      stdout.writeln('    ${r['path']}: ${issues.join(", ")}');
    }
  }
  stdout.writeln('========================================');
}
