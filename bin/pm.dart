import 'dart:io';

import 'package:args/args.dart';
import 'package:pub_semver/pub_semver.dart' as semver;
import 'package:pubspec_manager/pubspec_manager.dart'
    hide Version, VersionConstraint;

const _commandLowerMax = 'lower-max';
const _commandRaiseMax = 'raise-max';
const _commandRaiseMaxSdk = 'raise-max-sdk';
const _commandRaiseMin = 'raise-min';
const _commandRaiseMinSdk = 'raise-min-sdk';
const _commandSet = 'set';
const _commandSetSdk = 'set-sdk';

const _usageHeader = 'Usage: dart run pubmod <command> [arguments]';

Future<void> main(List<String> args) async {
  final exitCode = await _run(args);
  if (exitCode != 0) {
    // ignore: avoid_print
    stderr.writeln('pubmod failed with exit code $exitCode.');
  }
  exit(exitCode);
}

Future<int> _run(List<String> args) async {
  final parser = _buildParser();

  late ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln('');
    _printUsage(parser);
    return 64;
  }

  final showHelp = results['help'] as bool;
  if (showHelp) {
    _printUsage(parser);
    return 0;
  }

  final command = results.command;
  if (command == null) {
    _printUsage(parser);
    return 64;
  }

  final commandName = command.name;
  if (commandName == null) {
    _printUsage(parser);
    return 64;
  }
  final targetsSdk = _isSdkCommand(commandName);
  final rest = command.rest;
  late String dependencyName;
  late String versionText;
  if (targetsSdk) {
    if (rest.length != 1) {
      stderr.writeln(
        'Command "$commandName" requires exactly 1 argument: <version>',
      );
      stderr.writeln('');
      _printUsage(parser);
      return 64;
    }
    dependencyName = 'sdk';
    versionText = rest[0].trim();
    if (versionText.isEmpty) {
      stderr.writeln('Version must not be empty.');
      return 64;
    }
  } else {
    if (rest.length != 2) {
      stderr.writeln(
        'Command "$commandName" requires exactly 2 arguments: <dependency> <version>',
      );
      stderr.writeln('');
      _printUsage(parser);
      return 64;
    }

    dependencyName = rest[0].trim();
    versionText = rest[1].trim();
    if (dependencyName.isEmpty || versionText.isEmpty) {
      stderr.writeln('Dependency and version must not be empty.');
      return 64;
    }
  }

  final failOnParseError = results['fail-on-parse-error'] as bool;
  final recursive = results['recursive'] as bool;
  final tighten = results['tighten'] as bool;

  final op = _Operation.fromCommand(commandName);
  if (op == null) {
    stderr.writeln('Unknown command: $commandName');
    return 64;
  }

  if (op == _Operation.set) {
    try {
      semver.VersionConstraint.parse(versionText);
    } on FormatException catch (e) {
      stderr.writeln('Invalid version constraint "$versionText": ${e.message}');
      return 64;
    }
  } else {
    try {
      semver.Version.parse(versionText);
    } on FormatException catch (e) {
      stderr.writeln('Invalid version "$versionText": ${e.message}');
      return 64;
    }
  }

  final pubspecFiles = _findPubspecFiles(recursive: recursive);
  if (pubspecFiles.isEmpty) {
    return 0;
  }

  var hadParseError = false;
  for (final path in pubspecFiles) {
    PubSpec pubspec;
    try {
      pubspec = PubSpec.loadFromPath(path);
    } catch (e) {
      hadParseError = true;
      stderr.writeln('Unable to parse $path: $e');
      if (failOnParseError) {
        return 1;
      }
      continue;
    }

    final before = File(path).readAsStringSync();

    final updateMessages = <String>[];
    if (targetsSdk) {
      updateMessages
          .addAll(_applyToSdk(pubspec, op, versionText, tighten: tighten));
    } else {
      updateMessages.addAll(
        _applyToDependencies(
          pubspec.dependencies,
          dependencyName,
          op,
          versionText,
          tighten: tighten,
        ),
      );
      updateMessages.addAll(
        _applyToDependencies(
          pubspec.devDependencies,
          dependencyName,
          op,
          versionText,
          tighten: tighten,
        ),
      );
    }

    final changed = updateMessages.isNotEmpty;

    if (!changed) {
      continue;
    }

    final after = pubspec.toString();
    if (before == after) {
      continue;
    }

    pubspec.saveTo(path);
    for (final message in updateMessages) {
      stdout.writeln(message);
    }
  }

  if (failOnParseError && hadParseError) {
    return 1;
  }

  return 0;
}

List<String> _applyToDependencies(
  Dependencies dependencies,
  String dependencyName,
  _Operation operation,
  String inputVersion, {
  required bool tighten,
}) {
  final dependency = dependencies[dependencyName];
  if (dependency == null) {
    return const [];
  }

  if (dependency is! DependencyVersioned) {
    return const [];
  }

  final versionedDependency = dependency as DependencyVersioned;
  final currentText = versionedDependency.versionConstraint.trim();

  if (operation == _Operation.set) {
    final nextText = _toYamlConstraint(inputVersion.trim(), currentText);
    if (nextText == currentText) {
      return const [];
    }
    versionedDependency.versionConstraint = nextText;
    return [_buildUpdateMessage(dependency.name, currentText, nextText)];
  }

  final target = semver.Version.parse(inputVersion);
  final normalizedCurrent = _stripMatchingQuotes(currentText);

  semver.VersionConstraint currentConstraint;
  try {
    currentConstraint = semver.VersionConstraint.parse(normalizedCurrent);
  } on FormatException catch (e) {
    stderr.writeln(
      'Skipping ${dependency.name}: invalid version constraint "$currentText" (${e.message})',
    );
    return const [];
  }
  final bounds = _ConstraintBounds.fromConstraint(currentConstraint);
  if (bounds == null) {
    stderr.writeln(
      'Skipping ${dependency.name}: unsupported version constraint "$currentText"',
    );
    return const [];
  }

  final nextBounds = bounds.copy();
  switch (operation) {
    case _Operation.lowerMax:
      if (_hasLowerOrEqualExclusiveMax(bounds, target)) {
        return const [];
      }
      nextBounds.max = target;
      nextBounds.includeMax = false;
    case _Operation.raiseMax:
      if (_hasHigherOrEqualExclusiveMax(bounds, target)) {
        return const [];
      }
      nextBounds.max = target;
      nextBounds.includeMax = false;
    case _Operation.raiseMin:
      if (_hasHigherOrEqualInclusiveMin(bounds, target)) {
        return const [];
      }
      nextBounds.min = target;
      nextBounds.includeMin = true;
    case _Operation.set:
      throw StateError('Unexpected operation in bounds transform.');
  }

  if (!nextBounds.isValid()) {
    stderr.writeln(
      'Skipping ${dependency.name}: resulting range would be empty (${nextBounds.toConstraintString(tighten: false)})',
    );
    return const [];
  }

  final nextText = _toYamlConstraint(
    nextBounds.toConstraintString(tighten: tighten),
    currentText,
  );
  if (nextText == currentText) {
    return const [];
  }

  versionedDependency.versionConstraint = nextText;
  return [_buildUpdateMessage(dependency.name, currentText, nextText)];
}

List<String> _applyToSdk(
  PubSpec pubspec,
  _Operation operation,
  String inputVersion, {
  required bool tighten,
}) {
  final currentText = pubspec.environment.sdk.trim();
  if (currentText.isEmpty) {
    return const [];
  }

  if (operation == _Operation.set) {
    final nextText = _toYamlConstraint(inputVersion.trim(), currentText);
    if (nextText == currentText) {
      return const [];
    }
    pubspec.environment.sdk = nextText;
    return [_buildUpdateMessage('sdk', currentText, nextText)];
  }

  final target = semver.Version.parse(inputVersion);
  final normalizedCurrent = _stripMatchingQuotes(currentText);

  semver.VersionConstraint currentConstraint;
  try {
    currentConstraint = semver.VersionConstraint.parse(normalizedCurrent);
  } on FormatException catch (e) {
    stderr.writeln(
      'Skipping sdk: invalid version constraint "$currentText" (${e.message})',
    );
    return const [];
  }

  final bounds = _ConstraintBounds.fromConstraint(currentConstraint);
  if (bounds == null) {
    stderr.writeln(
      'Skipping sdk: unsupported version constraint "$currentText"',
    );
    return const [];
  }

  final nextBounds = bounds.copy();
  switch (operation) {
    case _Operation.lowerMax:
      if (_hasLowerOrEqualExclusiveMax(bounds, target)) {
        return const [];
      }
      nextBounds.max = target;
      nextBounds.includeMax = false;
    case _Operation.raiseMax:
      if (_hasHigherOrEqualExclusiveMax(bounds, target)) {
        return const [];
      }
      nextBounds.max = target;
      nextBounds.includeMax = false;
    case _Operation.raiseMin:
      if (_hasHigherOrEqualInclusiveMin(bounds, target)) {
        return const [];
      }
      nextBounds.min = target;
      nextBounds.includeMin = true;
    case _Operation.set:
      throw StateError('Unexpected operation in bounds transform.');
  }

  if (!nextBounds.isValid()) {
    stderr.writeln(
      'Skipping sdk: resulting range would be empty (${nextBounds.toConstraintString(tighten: false)})',
    );
    return const [];
  }

  final nextText = _toYamlConstraint(
    nextBounds.toConstraintString(tighten: tighten),
    currentText,
  );
  if (nextText == currentText) {
    return const [];
  }

  pubspec.environment.sdk = nextText;
  return [_buildUpdateMessage('sdk', currentText, nextText)];
}

ArgParser _buildParser() {
  final parser = ArgParser()
    ..addFlag('help',
        abbr: 'h', negatable: false, help: 'Print this usage information.')
    ..addFlag(
      'fail-on-parse-error',
      negatable: false,
      help:
          'If a pubspec.yaml cannot be parsed, fail immediately and set the exit code',
    )
    ..addFlag(
      'recursive',
      abbr: 'r',
      negatable: false,
      help: 'Recurse through subdirectories and run on all pubspec.yaml files',
    )
    ..addFlag(
      'tighten',
      defaultsTo: true,
      help:
          'When updating range constraints, rewrite equivalent ranges as caret constraints (for example >=3.0.0 <4.0.0 to ^3.0.0). Disable with --no-tighten.',
    );

  for (final command in [
    _commandLowerMax,
    _commandRaiseMax,
    _commandRaiseMaxSdk,
    _commandRaiseMin,
    _commandRaiseMinSdk,
    _commandSet,
    _commandSetSdk,
  ]) {
    parser.addCommand(command);
  }

  return parser;
}

void _printUsage(ArgParser parser) {
  stdout.writeln(_usageHeader);
  stdout.writeln('');
  stdout.writeln('Global options:');
  stdout.writeln(parser.usage);
  stdout.writeln('Available commands:');
  stdout.writeln('(dependencies)');
  stdout.writeln('  set         Set the version of a dependency');
  stdout.writeln(
      '  lower-max   Lower the maximum allowed version (exclusive) of a dependency.');
  stdout.writeln(
      '  raise-max   Raise the maximum allowed version (exclusive) of a dependency.');
  stdout.writeln(
      '  raise-min   Raise the minimum allowed version (inclusive) of a dependency.');
  stdout.writeln('(sdk)');
  stdout.writeln(
      '  set-sdk     Set the SDK version constraint in environment.sdk.');
  stdout.writeln(
      '  raise-max-sdk Raise the maximum allowed SDK version (exclusive) in environment.sdk.');
  stdout.writeln(
      '  raise-min-sdk Raise the minimum allowed SDK version (inclusive) in environment.sdk.');
}

bool _isSdkCommand(String commandName) {
  return commandName == _commandSetSdk ||
      commandName == _commandRaiseMinSdk ||
      commandName == _commandRaiseMaxSdk;
}

List<String> _findPubspecFiles({required bool recursive}) {
  final root = Directory.current;
  if (!recursive) {
    final file = File('${root.path}${Platform.pathSeparator}pubspec.yaml');
    return file.existsSync() ? [file.absolute.path] : const [];
  }

  final paths = <String>{};
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }

    final parts = entity.path.split(Platform.pathSeparator);
    if (parts.contains('.git')) {
      continue;
    }

    if (parts.isEmpty || parts.last != 'pubspec.yaml') {
      continue;
    }
    paths.add(entity.absolute.path);
  }

  final result = paths.toList()..sort();
  return result;
}

bool _hasHigherOrEqualInclusiveMin(
  _ConstraintBounds bounds,
  semver.Version target,
) {
  final min = bounds.min;
  if (min == null) {
    return false;
  }
  final cmp = min.compareTo(target);
  if (cmp > 0) {
    return true;
  }
  if (cmp < 0) {
    return false;
  }
  return bounds.includeMin;
}

bool _hasHigherOrEqualExclusiveMax(
  _ConstraintBounds bounds,
  semver.Version target,
) {
  final max = bounds.max;
  if (max == null) {
    return false;
  }
  final cmp = max.compareTo(target);
  if (cmp > 0) {
    return true;
  }
  if (cmp < 0) {
    return false;
  }
  return !bounds.includeMax;
}

bool _hasLowerOrEqualExclusiveMax(
  _ConstraintBounds bounds,
  semver.Version target,
) {
  final max = bounds.max;
  if (max == null) {
    return false;
  }
  final cmp = max.compareTo(target);
  if (cmp < 0) {
    return true;
  }
  if (cmp > 0) {
    return false;
  }
  return !bounds.includeMax;
}

enum _Operation {
  lowerMax,
  raiseMax,
  raiseMin,
  set;

  static _Operation? fromCommand(String command) {
    switch (command) {
      case _commandLowerMax:
        return _Operation.lowerMax;
      case _commandRaiseMax:
      case _commandRaiseMaxSdk:
        return _Operation.raiseMax;
      case _commandRaiseMin:
      case _commandRaiseMinSdk:
        return _Operation.raiseMin;
      case _commandSet:
      case _commandSetSdk:
        return _Operation.set;
    }
    return null;
  }
}

class _ConstraintBounds {
  _ConstraintBounds({
    this.min,
    this.includeMin = true,
    this.max,
    this.includeMax = false,
  });

  semver.Version? min;
  bool includeMin;
  semver.Version? max;
  bool includeMax;

  static _ConstraintBounds? fromConstraint(
      semver.VersionConstraint constraint) {
    if (constraint == semver.VersionConstraint.any) {
      return _ConstraintBounds(min: null, max: null);
    }

    if (constraint is semver.Version) {
      return _ConstraintBounds(
        min: constraint,
        includeMin: true,
        max: constraint,
        includeMax: true,
      );
    }

    if (constraint is semver.VersionRange) {
      return _ConstraintBounds(
        min: constraint.min,
        includeMin: constraint.includeMin,
        max: constraint.max,
        includeMax: constraint.includeMax,
      );
    }

    return null;
  }

  _ConstraintBounds copy() => _ConstraintBounds(
        min: min,
        includeMin: includeMin,
        max: max,
        includeMax: includeMax,
      );

  bool isValid() {
    if (min == null || max == null) {
      return true;
    }
    final cmp = min!.compareTo(max!);
    if (cmp < 0) {
      return true;
    }
    if (cmp > 0) {
      return false;
    }
    return includeMin && includeMax;
  }

  String toConstraintString({required bool tighten}) {
    if (tighten) {
      final tightened = _toCaretConstraint();
      if (tightened != null) {
        return tightened;
      }
    }

    if (min == null && max == null) {
      return 'any';
    }

    if (min != null && max != null && min == max && includeMin && includeMax) {
      return min.toString();
    }

    final pieces = <String>[];
    if (min != null) {
      pieces.add('${includeMin ? '>=' : '>'}$min');
    }
    if (max != null) {
      final displayMax = includeMax ? max! : _normalizeExclusiveMax(max!);
      pieces.add('${includeMax ? '<=' : '<'}$displayMax');
    }
    return pieces.join(' ');
  }

  String? _toCaretConstraint() {
    if (min == null || max == null) {
      return null;
    }
    if (!includeMin || includeMax) {
      return null;
    }

    final minVersion = min!;
    if (minVersion.isPreRelease) {
      return null;
    }

    final expectedMax = _caretUpperBound(minVersion);
    final normalizedMax = _normalizeExclusiveMax(max!);
    if (expectedMax != normalizedMax) {
      return null;
    }

    return '^$minVersion';
  }
}

semver.Version _caretUpperBound(semver.Version version) {
  if (version.major > 0) {
    return semver.Version(version.major + 1, 0, 0);
  }
  if (version.minor > 0) {
    return semver.Version(0, version.minor + 1, 0);
  }
  return semver.Version(0, 0, version.patch + 1);
}

semver.Version _normalizeExclusiveMax(semver.Version version) {
  if (!version.isPreRelease) {
    return version;
  }

  final pre = version.preRelease;
  if (pre.length == 1 && pre.first == 0) {
    return semver.Version(version.major, version.minor, version.patch);
  }

  return version;
}

String _stripMatchingQuotes(String text) {
  if (text.length < 2) {
    return text;
  }

  final first = text[0];
  final last = text[text.length - 1];
  if ((first == '\'' || first == '"') && first == last) {
    return text.substring(1, text.length - 1).trim();
  }
  return text;
}

String _toYamlConstraint(String value, String existingValue) {
  final trimmed = value.trim();
  final needsQuoting = RegExp(r'\s').hasMatch(trimmed);
  if (!needsQuoting) {
    return trimmed;
  }

  final existingTrimmed = existingValue.trim();
  final useDoubleQuote = existingTrimmed.length >= 2 &&
      existingTrimmed.startsWith('"') &&
      existingTrimmed.endsWith('"');

  if (useDoubleQuote) {
    final escaped = trimmed.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    return '"$escaped"';
  }

  final escaped = trimmed.replaceAll("'", "''");
  return "'$escaped'";
}

String _buildUpdateMessage(String name, String before, String after) {
  final beforeDisplay = _formatConstraintForMessage(before);
  final afterDisplay = _formatConstraintForMessage(after);
  return '$name $beforeDisplay updated to $afterDisplay';
}

String _formatConstraintForMessage(String value) {
  final normalized = _stripMatchingQuotes(value.trim());
  if (_looksLikeRangeConstraint(normalized)) {
    final escaped = normalized.replaceAll("'", "''");
    return "'$escaped'";
  }
  return normalized;
}

bool _looksLikeRangeConstraint(String value) {
  if (value.contains(' ') || value.contains('||')) {
    return true;
  }
  return value.startsWith('>=') ||
      value.startsWith('<=') ||
      value.startsWith('>') ||
      value.startsWith('<');
}
