import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory scratchRoot;

  setUp(() {
    scratchRoot = Directory.systemTemp.createTempSync('pm_test_');
  });

  tearDown(() {
    if (scratchRoot.existsSync()) {
      scratchRoot.deleteSync(recursive: true);
    }
  });

  group('pm CLI', () {
    test('set-sdk updates environment sdk constraint in current pubspec',
        () async {
      final workDir = _copyFixture('sdk_basic', scratchRoot);

      final result = await _runPm(
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

      final content =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();
      expect(_hasSdkConstraint(content, '>=3.3.0 <4.0.0'), isTrue);
    });

    test('raise-min-sdk updates minimum sdk in recursive scan', () async {
      final workDir = _copyFixture('sdk_recursive', scratchRoot);

      final result = await _runPm(
        ['raise-min-sdk', '3.4.0', '-r', '--no-tighten'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());

      final root =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();

      expect(_hasSdkConstraint(root, '>=3.4.0 <4.0.0'), isTrue);
    });

    test('raise-max-sdk updates upper sdk bound in recursive scan', () async {
      final workDir = _copyFixture('sdk_recursive', scratchRoot);

      final result = await _runPm(
        ['raise-max-sdk', '5.0.0', '-r', '--no-tighten'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());

      final root =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();

      expect(_hasSdkConstraint(root, '>=3.0.0 <5.0.0'), isTrue);
    });

    test('sdk commands respect fail-on-parse-error', () async {
      final workDir = _copyFixture('sdk_recursive', scratchRoot);
      _writeMalformedPubspec(workDir, 'packages/bad/pubspec.yaml');

      final result = await _runPm(
        ['raise-min-sdk', '3.4.0', '--fail-on-parse-error', '-r'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('Unable to parse'));
    });

    test('set updates plain and hosted dependency styles', () async {
      final workDir = _copyFixture('basic', scratchRoot);

      final result = await _runPm(
        ['set', 'path', '1.9.1'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());
      expect(
          result.stdout.toString(), contains("path ^1.9.0 updated to 1.9.1"));

      final content =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();
      expect(content, contains('path: 1.9.1'));
      expect(content, contains('version: 1.9.1'));
    });

    test('raise-min updates root fixture during recursive scan', () async {
      final workDir = _copyFixture('recursive', scratchRoot);

      final result = await _runPm(
        ['raise-min', 'path', '1.9.1', '-r', '--no-tighten'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());
      expect(
        result.stdout.toString(),
        contains("path ^1.9.0 updated to '>=1.9.1 <2.0.0'"),
      );

      final root =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();

      expect(_hasConstraint(root, 'path', '>=1.9.1 <2.0.0'), isTrue);
    });

    test('raise-max then lower-max updates exclusive upper bound', () async {
      final workDir = _copyFixture('recursive', scratchRoot);

      final raiseResult = await _runPm(
        ['raise-max', 'path', '3.0.0', '-r', '--no-tighten'],
        workingDirectory: workDir.path,
      );
      expect(raiseResult.exitCode, 0, reason: raiseResult.stderr.toString());

      final loweredResult = await _runPm(
        ['lower-max', 'path', '2.5.0', '-r', '--no-tighten'],
        workingDirectory: workDir.path,
      );
      expect(loweredResult.exitCode, 0,
          reason: loweredResult.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(raiseResult.stdout.toString());
      _expectUpdateOutput(loweredResult.stdout.toString());
      expect(
        loweredResult.stdout.toString(),
        contains("path '>=1.9.0 <3.0.0' updated to '>=1.9.0 <2.5.0'"),
      );

      final root =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();

      expect(_hasConstraint(root, 'path', '>=1.9.0 <2.5.0'), isTrue);
    });

    test('tighten defaults to true for dependency updates in recursive scan',
        () async {
      final workDir = _copyFixture('recursive', scratchRoot);

      final result = await _runPm(
        ['raise-min', 'path', '1.9.1', '-r'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());
      expect(result.stdout.toString(), contains('updated to ^1.9.1'));

      final root =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();

      expect(_hasConstraint(root, 'path', '^1.9.1'), isTrue);
    });

    test('tighten defaults to true for sdk updates in recursive scan',
        () async {
      final workDir = _copyFixture('sdk_recursive', scratchRoot);

      final result = await _runPm(
        ['raise-min-sdk', '3.4.0', '-r'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());
      expect(result.stdout.toString(), contains('sdk'));
      expect(result.stdout.toString(), contains('updated to ^3.4.0'));

      final root =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();

      expect(_hasSdkConstraint(root, '^3.4.0'), isTrue);
    });

    test('--tighten supports 0.x caret compression', () async {
      final workDir = _writePubspecFixture(scratchRoot, '''
name: zero_major_fixture
version: 0.0.1
environment:
  sdk: '>=3.0.0 <4.0.0'
dependencies:
  path: '>=0.17.0 <0.19.0'
''');

      final result = await _runPm(
        ['raise-min', 'path', '0.18.2'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      _expectUpdateOutput(result.stdout.toString());

      final content =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();
      expect(_hasConstraint(content, 'path', '^0.18.2'), isTrue);
    });

    test('--tighten keeps non-equivalent ranges as ranges', () async {
      final workDir = _writePubspecFixture(scratchRoot, '''
name: crossing_major_fixture
version: 0.0.1
environment:
  sdk: '>=3.0.0 <4.0.0'
dependencies:
  path: '>=1.2.3 <4.0.0'
''');

      final result = await _runPm(
        ['raise-min', 'path', '1.3.0'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());

      final content =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();
      expect(_hasConstraint(content, 'path', '>=1.3.0 <4.0.0'), isTrue);
      expect(content, isNot(contains('path: ^1.3.0')));
    });

    test('--no-tighten opts out and preserves explicit range output', () async {
      final workDir = _copyFixture('recursive', scratchRoot);

      final result = await _runPm(
        ['raise-min', 'path', '1.9.1', '-r', '--no-tighten'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());

      final content =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();
      expect(_hasConstraint(content, 'path', '>=1.9.1 <2.0.0'), isTrue);
      expect(content, isNot(contains('path: ^1.9.1')));
    });

    test(
        'fail-on-parse-error returns non-zero when recursive scan hits malformed pubspec',
        () async {
      final workDir = _copyFixture('recursive', scratchRoot);
      _writeMalformedPubspec(workDir, 'packages/bad/pubspec.yaml');

      final result = await _runPm(
        ['set', 'path', '1.9.1', '--fail-on-parse-error', '-r'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('Unable to parse'));
    });

    test('tighten raises minimums from pubspec.lock by default', () async {
      final workDir = _copyFixture('tighten_basic', scratchRoot);

      final result = await _runPm(
        ['tighten'],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());

      final content =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();

      expect(_hasConstraint(content, 'args', '^2.3.0'), isTrue);
      expect(_hasConstraint(content, 'path', '^1.9.1'), isTrue);
      expect(_hasConstraint(content, 'version', '>=0.2.3 <1.0.0'), isTrue);
      expect(_hasConstraint(content, 'test', '^1.25.15'), isTrue);
    });

    test('tighten accepts a custom lockfile path', () async {
      final workDir = _copyFixture('tighten_basic', scratchRoot);
      final customLockPath = p.join(workDir.path, 'custom.lock');

      File(p.join(workDir.path, 'pubspec.lock')).renameSync(customLockPath);

      final result = await _runPm(
        ['tighten', customLockPath],
        workingDirectory: workDir.path,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      await _assertPubGetParses(workDir.path);
      _expectUpdateOutput(result.stdout.toString());

      final content =
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync();

      expect(_hasConstraint(content, 'args', '^2.3.0'), isTrue);
      expect(_hasConstraint(content, 'path', '^1.9.1'), isTrue);
      expect(_hasConstraint(content, 'version', '>=0.2.3 <1.0.0'), isTrue);
      expect(_hasConstraint(content, 'test', '^1.25.15'), isTrue);
    });
  });
}

Future<void> _assertPubGetParses(String workingDirectory) async {
  final result = await Process.run('dart', ['pub', 'get'],
      workingDirectory: workingDirectory);
  expect(
    result.exitCode,
    0,
    reason:
        'dart pub get failed in $workingDirectory\nstdout: ${result.stdout}\nstderr: ${result.stderr}',
  );
}

Directory _copyFixture(String fixtureName, Directory parent) {
  final source = Directory(
    p.join(_repoRoot.path, 'test', 'fixtures', 'pm', fixtureName),
  );
  if (!source.existsSync()) {
    throw StateError('Fixture not found: ${source.path}');
  }

  final target = Directory(p.join(parent.path, fixtureName))
    ..createSync(recursive: true);
  _copyDirectory(source, target);
  return target;
}

Directory _writePubspecFixture(Directory parent, String pubspecContent) {
  final workDir = Directory(
      p.join(parent.path, 'custom_${DateTime.now().microsecondsSinceEpoch}'))
    ..createSync(recursive: true);
  File(p.join(workDir.path, 'pubspec.yaml'))
      .writeAsStringSync(pubspecContent.trimLeft());
  return workDir;
}

void _writeMalformedPubspec(Directory root, String relativePath) {
  File(p.join(root.path, relativePath))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
name: malformed_fixture
version: 0.0.1
dependencies:
  foo: ^1.0.0
  foo: ^2.0.0
''');
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

Future<ProcessResult> _runPm(
  List<String> args, {
  required String workingDirectory,
}) {
  final packageConfig =
      p.join(_repoRoot.path, '.dart_tool', 'package_config.json');
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
    reason:
        'Expected update output lines in format: <dep> <before> updated to <after>',
  );
}
