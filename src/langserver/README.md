# Language Server

## Description
This is a language server that supports both the high and low level languages
in this project.  We haven't decided the name for things yet, but currently the
language recognizes the extensions .mcl (Melancolang) for the high level
language and .vmd (VeMod) for the low level language.

The language server currently only supports the low level language, and only
implements diagnostics and code completion (it doesn't support requests like
go-to-defintion etc.).

## Options
* `--log-level <LEVEL>`: Set the log level. Can be one of 'debug', 'info', 'warn', 'err'.
* `--disable <FEATURE>`: Disable a feature. Can be one of 'hover', 'completion', 'diagnostics'. Can be specified multiple times.

## Integration
See the [editors](../../editor/) folder for integration with editors.
