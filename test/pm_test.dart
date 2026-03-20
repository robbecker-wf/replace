import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory scratchRoot;

  setUp(() {
    scratchRoot = Directory.systemTemp.createTempSync('pubmod_test_');
  });

  tearDown(() {
    if (scratchRoot.existsSync()) {
      scratchRoot.deleteSync(recursive: true);
    }
  });

  group('pubmod CLI', () {
    test('set-sdk updates environment sdk constraint in current pubspec', () async {
      final workDir = _copyFixture('sdk_basic', scratchRoot);

      final result = await _runPubmod(
        ['set-sdk', '>=3.3.0 <4.0.0'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());
      expect(
        result.stdout.toString(),
        contains("sdk '>=3.0.0 <4.0.0' updated to '>=3.3.0 <4.0.0'"),
      );

      final content = File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();
      expect(_hasSdkConstraint(content, '>=3.3.0 <4.0.0'), isTrue);
    });

    test('raise-min-sdk updates minimum sdk recursively', () async {
      final workDir = _copyFixture('sdk_recursive', scratchRoot);

      final result = await _runPubmod(
        ['raise-min-sdk', '3.4.0', '-r'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());

      final root = File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();
      final child =
          File(p.join(workDir.path, 'packages', 'child', 'pubspec.yaml')).readAsStringSync();
      final doubleQuoted = File(
        p.join(workDir.path, 'packages', 'double_quoted', 'pubspec.yaml'),
      ).readAsStringSync();
      final noEnv =
          File(p.join(workDir.path, 'packages', 'no_env', 'pubspec.yaml')).readAsStringSync();

      expect(_hasSdkConstraint(root, '>=3.4.0 <4.0.0'), isTrue);
      expect(_hasSdkConstraint(child, '>=3.4.0 <4.0.0'), isTrue);
      expect(_hasSdkConstraint(doubleQuoted, '>=3.4.0 <4.0.0'), isTrue);
      expect(noEnv, isNot(contains('environment:')));
    });

    test('raise-max-sdk updates upper sdk bound recursively', () async {
      final workDir = _copyFixture('sdk_recursive', scratchRoot);

      final result = await _runPubmod(
        ['raise-max-sdk', '5.0.0', '-r'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());

      final root = File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();
      final child =
          File(p.join(workDir.path, 'packages', 'child', 'pubspec.yaml')).readAsStringSync();
      final doubleQuoted = File(
        p.join(workDir.path, 'packages', 'double_quoted', 'pubspec.yaml'),
      ).readAsStringSync();

      expect(_hasSdkConstraint(root, '>=3.0.0 <5.0.0'), isTrue);
      expect(_hasSdkConstraint(child, '>=3.1.0 <5.0.0'), isTrue);
      expect(_hasSdkConstraint(doubleQuoted, '>=3.2.0 <5.0.0'), isTrue);
    });

    test('sdk commands respect fail-on-parse-error', () async {
      final workDir = _copyFixture('sdk_recursive', scratchRoot);

      final result = await _runPubmod(
        ['raise-min-sdk', '3.4.0', '--fail-on-parse-error', '-r'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('Unable to parse'));
    });

    test('set updates plain and hosted dependency styles', () async {
      final workDir = _copyFixture('basic', scratchRoot);

      final result = await _runPubmod(
        ['set', 'path', '1.9.1'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());
      expect(result.stdout.toString(), contains("path ^1.9.0 updated to 1.9.1"));

      final content = File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();
      expect(content, contains('path: 1.9.1'));
      expect(content, contains('version: 1.9.1'));
    });

    test('raise-min updates recursive plain constraints including quoted ranges', () async {
      final workDir = _copyFixture('recursive', scratchRoot);

      final result = await _runPubmod(
        ['raise-min', 'path', '1.9.1', '-r'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());
      expect(
        result.stdout.toString(),
        contains("path '>=1.8.0 <2.0.0' updated to '>=1.9.1 <2.0.0'"),
      );
      expect(
        result.stdout.toString(),
        contains("path '>=1.7.0 <2.0.0' updated to '>=1.9.1 <2.0.0'"),
      );

      final root = File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();
      final child =
          File(p.join(workDir.path, 'packages', 'child', 'pubspec.yaml')).readAsStringSync();
      final doubleQuoted = File(
        p.join(workDir.path, 'packages', 'double_quoted', 'pubspec.yaml'),
      ).readAsStringSync();
      final hosted =
          File(p.join(workDir.path, 'packages', 'hosted', 'pubspec.yaml')).readAsStringSync();

      expect(_hasConstraint(root, 'path', '>=1.9.1 <2.0.0'), isTrue);
      expect(_hasConstraint(child, 'path', '>=1.9.1 <2.0.0'), isTrue);
      expect(_hasConstraint(doubleQuoted, 'path', '>=1.9.1 <2.0.0'), isTrue);
      expect(_hasConstraint(hosted, 'version', '>=1.9.1 <2.0.0'), isTrue);
    });

    test('raise-max and lower-max update exclusive upper bound only when needed', () async {
      final workDir = _copyFixture('recursive', scratchRoot);

      final raiseResult = await _runPubmod(
        ['raise-max', 'path', '3.0.0', '-r'],
        workingDirectory: workDir.path,
      );
      expect(raiseResult.exitCode, 0, reason: raiseResult.stderr.toString());

      final loweredResult = await _runPubmod(
        ['lower-max', 'path', '2.5.0', '-r'],
        workingDirectory: workDir.path,
      );
      expect(loweredResult.exitCode, 0, reason: loweredResult.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(raiseResult.stdout.toString());
      _expectUpdateOutput(loweredResult.stdout.toString());
      expect(
        loweredResult.stdout.toString(),
        contains("path '>=1.8.0 <3.0.0' updated to '>=1.8.0 <2.5.0'"),
      );

      final root = File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();
      final child =
          File(p.join(workDir.path, 'packages', 'child', 'pubspec.yaml')).readAsStringSync();
      final doubleQuoted = File(
        p.join(workDir.path, 'packages', 'double_quoted', 'pubspec.yaml'),
      ).readAsStringSync();
      final hosted =
          File(p.join(workDir.path, 'packages', 'hosted', 'pubspec.yaml')).readAsStringSync();

      expect(_hasConstraint(root, 'path', '>=1.9.0 <2.5.0'), isTrue);
      expect(_hasConstraint(child, 'path', '>=1.8.0 <2.5.0'), isTrue);
      expect(_hasConstraint(doubleQuoted, 'path', '>=1.7.0 <2.5.0'), isTrue);
      expect(_hasConstraint(hosted, 'version', '>=1.8.0 <2.5.0'), isTrue);
    });

    test('fail-on-parse-error returns non-zero on malformed pubspec', () async {
      final workDir = _copyFixture('recursive', scratchRoot);

      final result = await _runPubmod(
        ['set', 'path', '1.9.1', '--fail-on-parse-error', '-r'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('Unable to parse'));
    });
  });
}

Future<void> _assertPubGetParses(String workingDirectory) async {
  final result = await Process.run('dart', ['pub', 'get'], workingDirectory: workingDirectory);
  expect(
    result.exitCode,
    0,
    reason: 'dart pub get failed in $workingDirectory\nstdout: ${result.stdout}\nstderr: ${result.stderr}',
  );
}

Directory _copyFixture(String fixtureName, Directory parent) {
  final source = Directory(
    p.join(_repoRoot.path, 'test', 'fixtures', 'pubmod', fixtureName),
  );
  if (!source.existsSync()) {
    throw StateError('Fixture not found: ${source.path}');
  }

  final target = Directory(p.join(parent.path, fixtureName))..createSync(recursive: true);
  _copyDirectory(source, target);
  return target;
}

void _copyDirectory(Directory source, Directory target) {
  for (final entity in source.listSync(recursive: true, followLinks: false)) {
    final relative = p.relative(entity.path, from: source.path);
    final destinationPath = p.join(target.path, relative);

    if (entity is Directory) {
      Directory(destinationPath).createSync(recursive: true);
    } else if (entity is File) {
      File(destinationPath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(entity.readAsBytesSync());
    }
  }
}

Future<ProcessResult> _runPubmod(
  List<String> args, {
  required String workingDirectory,
}) {
  final packageConfig = p.join(_repoRoot.path, '.dart_tool', 'package_config.json');
  final script = p.join(_repoRoot.path, 'bin', 'pm.dart');

  return Process.run(
    'dart',
    ['--packages=$packageConfig', script, ...args],
    workingDirectory: workingDirectory,
  );
}

Directory get _repoRoot => Directory.current;

bool _hasConstraint(String content, String key, String constraint) {
  return content.contains("$key: $constraint") ||
      content.contains("$key: '$constraint'") ||
      content.contains('$key: "$constraint"');
}

bool _hasSdkConstraint(String content, String constraint) {
  return content.contains('sdk: $constraint') ||
      content.contains("sdk: '$constraint'") ||
      content.contains('sdk: "$constraint"');
}

void _expectUpdateOutput(String stdout) {
  expect(
    stdout,
    matches(RegExp(r'^[^\s]+ .+ updated to .+$', multiLine: true)),
    reason: 'Expected update output lines in format: <dep> <before> updated to <after>',
  );
}
