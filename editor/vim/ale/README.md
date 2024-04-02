# Vim/ALE integration for the language server

## Description
Proof of concept for integrating the INDA23++ virtual machine language server
with Vim/ALE.  The server is configured to write logging output to a named pipe
`mclls.log`.  Before anything is displayed in Vim, you need to read from it, or
alternatively change `fifo` to `file` or `stderr` in `mclls.vim`

We haven't really decided the names for things yet, but the server now recognize
.mcl (Melancolang) for the high level language and .vmd (VeMod) for the low level
language.

## Usage
`:source mclls.vim`
