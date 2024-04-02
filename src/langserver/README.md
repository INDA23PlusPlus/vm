# Language Server

## Description
This is a language server that supports both the high and low level languages in this project.
We haven't decided the name for things yet, but currently the language recognizes the extensions
.mcl (Melancolang) for the high level language and .vmd (VeMod) for the low level language.

The language server currently only supports the low level language, and only publishes diagnostics
(it doesn't support requests like go-to-defintion etc.).

## Options
* `--log-output <OUTPUT>` - Specifies how to log output. Can be one of `stderr`, `file` or `fifo`. The default is `stderr`.
* `--log-file <FILE>` - Specifies the path to the log file/named pipe. The default is `mclls.log`.

## Integration
See the [editors](../../editor/) folder for integration with editors.
