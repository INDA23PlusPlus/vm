#!/usr/bin/env bash

# Wrapper script for language server
# to redirect log to named pipe

mkfifo mclls.log 2>/dev/null || true
mclls 2>mclls.log
