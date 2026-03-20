# replace
Easy to use cross-platform regex replace command line util.
Can't remember the arguments to the `find` command? or how `xargs` works?
Maybe `sed` is a little different on your Mac than in Linux?

Forget all that stuff and just `replace string newval **/*.dart`

This tool is pretty basic and there aren't a lot of safeguards. It can run recursively and replace things in files that weren't intended. Use caution when replacing.
It's meant to be used in a directory under source control so you can see
what files have been changed using a diff.

It ignores dotfiles (especially the .git directory) except these
  - .gitignore
  - .pubignore
  - .travis.yml
  - .travis.yaml

Globs don't seem to go into dotfile directories by default so if you want to do that, just
include another glob in the command for those (Ex: `replace fish zebra .github/**.md **/*.md`)

If you need to replace in dotfiles other than these, you can submit a PR to this repo to
allow it or work around it by renaming the file, replacing, and renaming it back.

### Installing
`pub global activate replace`

This installs both command line tools from this package:
- `replace` for regex find/replace in files
- `pm` for editing dependency constraints in pubspec.yaml files

or more advanced install
- clone the project
- `pub get`
- `dart compile exe bin/replace.dart -o replace`
- `dart compile exe bin/pm.dart -o pm`
- Place the `replace` and `pm` executable in your path

### How to use replace
`replace <regexp> <replacement> <glob_file_or_dir> ...`

This means you can pass as many globs, directory names, or filenames
as the 3rd and after paramter. This works nicely with glob expansion
if your shell supports it.
Example `replace aword replacementword **/*.md`

If you're having problem with your shell interpreting characters as
shell control characters, and or you need spaces in your regex or
replacement, you can use quotes and `noglob`.

Example: `noglob replace "key & peele" "ren || stimpy" **/*.md`

Regexes and globs are Dart style
Glob Syntax: https://pub.dev/packages/glob#syntax

The replacement may contain references to the capture groups in regexp using a backslash followed by the group number. Backslashes not followed by a number return the character immediately following them.

More Examples:

Simple strings and filename
`replace word "lots of words" menu.txt`

Regex and glob (w/ quotes around arguments)
`replace "(war).*(worlds)" "\1 of the monkeys" **`

Match a word at the beginning of a line
`replace "^chowder" soup menu.txt`

Match a word at the end of a line
`replace "dessert$" cookies menu.txt`

## How to use pm

`pm` updates dependency version constraints in one or more pubspec.yaml files.

### Usage

`pm [global options] <command> <dependency> <version>`

Global options:
- `-h, --help` Print usage information
- `-r, --recursive` Recurse through subdirectories and process all pubspec.yaml files
- `--fail-on-parse-error` Exit with non-zero if any pubspec.yaml cannot be parsed

Commands:
- `set` Set dependency constraint exactly as provided
- `set-sdk` Set `environment.sdk` constraint exactly as provided
- `raise-min` Raise the minimum bound (inclusive) of a version range
- `raise-min-sdk` Raise the minimum `environment.sdk` bound (inclusive)
- `raise-max` Raise the maximum bound (exclusive) of a version range
- `raise-max-sdk` Raise the maximum `environment.sdk` bound (exclusive)
- `lower-max` Lower the maximum bound (exclusive) of a version range

Notes:
- Updates both `dependencies` and `dev_dependencies`
- SDK commands update `environment.sdk` only
- `set` accepts any valid Dart version constraint, for example `^1.9.0` or `'>=1.9.0 <2.0.0'`
- `set-sdk` accepts any valid Dart SDK constraint, for example `'>=3.3.0 <4.0.0'`
- `raise-min`, `raise-max`, and `lower-max` expect a specific semantic version, for example `1.9.1`
- `raise-min-sdk` and `raise-max-sdk` expect a specific semantic version, for example `3.4.0`

### Examples

Set a dependency version:

```sh
pm set path 1.9.1
```

Set a single version to a range constraint:

```sh
pm set path '>=1.9.0 <2.0.0'
```

Before:

```yaml
dependencies:
  path: 1.9.1
```

After:

```yaml
dependencies:
  path: '>=1.9.0 <2.0.0'
```

Raise minimum version recursively across a monorepo:

```sh
pm raise-min path 1.9.1 -r
```

Range to single version when the new minimum meets or exceeds the old maximum:

```sh
pm raise-min path 1.9.1
```

Before:

```yaml
dependencies:
  path: '>=1.8.0 <1.9.1'
```

After:

```yaml
dependencies:
  path: 1.9.1
```

Range to narrower range when the upper bound is still greater than the new minimum:

```sh
pm raise-min path 1.9.1
```

Before:

```yaml
dependencies:
  path: '>=1.8.0 <2.0.0'
```

After:

```yaml
dependencies:
  path: '>=1.9.1 <2.0.0'
```

Lower max version and fail if any pubspec is malformed:

```sh
pm lower-max path 2.5.0 -r --fail-on-parse-error
```

Set SDK constraint:

```sh
pm set-sdk '>=3.3.0 <4.0.0'
```

Raise SDK minimum recursively across a monorepo:

```sh
pm raise-min-sdk 3.4.0 -r
```

Raise SDK maximum recursively:

```sh
pm raise-max-sdk 5.0.0 -r
```
