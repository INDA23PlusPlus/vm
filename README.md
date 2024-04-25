# VeMod ![Tests](https://github.com/INDA23PlusPLus/vm/actions/workflows/zig.yml/badge.svg?event=push)
VeMod is a virtual stack machine written in Zig, with an associated assembly language and higher level
language (Melancolang).

## Prerequisites:
* Zig compiler (0.11.0)

## Installation
```bash
git clone https://github.com/INDA23PlusPlus/vm
cd vm
zig build vemod --prefix <installation path>
```

## Usage
VeMod can run programs from source directly, or compile it to a vbf-file (VeMod
Binary Format) with the -c flag. 

## Examples
Run a program written in VeMod assembly:
```bash
vemod program.vmd
```

Compile a program written in VeMod assembly:
```bash
vemod -c program.vmd -o program.vbf
```

Run a compiled program:
```bash
vemod program.vbf
```

To view all options, run
```bash
vemod -h
```

Syntax and instruction reference for VeMod assembly can be found in the [docs]
(docs/) directory. Code samples can be found in the [examples](examples/)
directory.

## Language server
The VeMod language server (vmdls) can be installed with the command
```bash
zig build vmdls --prefix <installation path>
```

For integration with various editors, see the [editor](editor/) folder.
vmdls can produce diagnostics, completions and hover information
for VeMod assembly. Too view available options, run
```bash
vmdls --help
```
