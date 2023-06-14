# glyphspython

**NOTE:** this project is super experimental and has been abandoned as the dependency doesn't support arm64. It's here as a proof-of-concept for reference just in case. This tool was originally designed to be the `ffpython` equivalent in FontForge.

An attempt to provide a Python interpreter which works as a headless version of Glyphs.app.

## Prerequisites

- OS X 10.9.x or later
- Glyphs 2.3.x or later

Make sure that your `Glyphs.app` exists in the `/Applications` directory.

## Installation

Unzip the archive and run `glyphspython` from the shell.

## Usage

Just works as a vanilla Python interpreter except you have an access to the classes available in Glyphs.app.

```sh
$ glyphspython -c 'print(Glyphs.versionNumber)'
2.6
```

```sh
$ glyphspython
Python 2.7.16 (default, Jan 27 2020, 04:46:15) 
[GCC 4.2.1 Compatible Apple LLVM 10.0.1 (clang-1001.0.37.14)] on darwin
Type "help", "copyright", "credits" or "license" for more information.
>>> Glyphs.versionNumber
2.6
```
In case you need register a license before running a script, pass `--register-license <path-to-license-file>` to the command:

```sh
$ glyphspython --register-license 'John Doe.glyphs2License'
```

If you are interested in running a specific version of Glyphs apart from the latest stable release, set the environment variable `GLYPHSAPP_PATH` and give the location for the alternative Glyphs installation you want to use:

```sh
$ GLYPHSAPP_PATH='/Applications/Glyphs 2.4.1 (983).app' glyphspython -c 'print(Glyphs.versionNumber)'
2.4
```

The versions and the locations of your Glyphs installation can be listed via the `--list-versions` option:

```sh
$ glyphspython --list-versions
2.6.4 (1286)	/Applications/Glyphs.app
2.6.3 (1271)	/Applications/Glyphs 2.6.3 (1271).app
2.6.2 (1268)	/Applications/Glyphs 2.6.2 (1268).app
2.6.1 (1230)	/Applications/Glyphs 2.6.1 (1230).app
2.5.1 (1141)	/Applications/Glyphs 2.5.1 (1141).app
2.4.4 (1075)	/Applications/Glyphs 2.4.4 (1075).app
2.4.3 (1064)	/Applications/Glyphs 2.4.3 (1064).app
2.4.1 (983)	/Applications/Glyphs 2.6.3 (1271).app
2.3.1 (897)	/Applications/Glyphs 2.3.1 (897).app
2.3 (895)	/Applications/Glyphs 2.3 (895).app
```

## License

Apache License 2.0
