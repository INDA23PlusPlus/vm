<div align="center">
<h1>VeMod</h1>

<a href="#installation">Installation</a> | <a href="#visual-studio-code">VS Code Extension</a>

![Tests](https://github.com/INDA23PlusPLus/vm/actions/workflows/zig.yml/badge.svg?event=push) ![Extension](https://github.com/INDA23PlusPLus/vm/actions/workflows/vscode.yml/badge.svg?event=push)
</div>

VeMod is a virtual stack machine written in Zig, with an associated assembly language and two high-level
languages: the functional **Blue** language, and the imperative **Melancolang**.

## Prerequisites:
* Zig compiler (0.13.0)

## Installation
```shellsession
git clone https://github.com/INDA23PlusPlus/vm
cd vm
zig build vemod --prefix <installation path>
```

## Usage
VeMod can run programs from source directly, or compile them to a vbf-file (VeMod
Binary Format) with the -c flag. 

## Examples
Run a program written in VeMod assembly:
```shellsession
vemod program.vmd
```

Compile a program written in VeMod assembly:
```shellsession
vemod -c program.vmd -o program.vbf
```

Run a compiled program:
```shellsession
vemod program.vbf
```

Run a Blue expression supplied as a command-line argument:
```shellsession
vemod -p "print \"Hello\" . -> 0"
```

Run the Blue REPL:
```shellsession
vemod --repl
>>> let
        square x = x * x;
    in square 5

25
>>>
```

To view all options, run
```shellsession
vemod -h
```

Language references can be found in the [docs](docs/)
directory. Code samples can be found in the [examples](examples/) directory.

## Language server
The VeMod language server (vmdls) can be installed with the command
```shellsession
zig build vmdls --prefix <installation path>
```

For integration with various editors, see the [editor](editor/) folder.
vmdls can produce diagnostics, completions and hover information
for VeMod assembly. To view available options, run
```shellsession
vmdls --help
```

### Visual Studio Code
To install the language server in Visual Studio Code, download the VS Code
extension here:

[Download](https://nightly.link/INDA23PlusPlus/vm/workflows/vscode/main/vscode-vemod.zip)

Installation Instructions:
- download the zip above
- unzip the file
- inside Visual Studio Code, go to the "Extensions" tab
- press the three dots `...`
- click `Install from VSIX...`
- choose the `.vsix` file from the zip
- Done! You may now delete the zip and the `.vsix` file.

To update the extension, uninstall it and then install the new version.

The first time you run the extension, you will need to choose a path for the
`vmdls` binary if you do not have it on your `PATH`. This is done from the
Visual Studio Code settings under Extensions > VeMod.
