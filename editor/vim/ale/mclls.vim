autocmd BufNewFile,BufRead *.mcl set filetype=mcl

call ale#linter#Define('mcl', {
\   'name': 'mclls',
\   'lsp': 'stdio',
\   'executable': '../../../zig-out/bin/langserver',
\   'command': '%e',
\   'project_root': '.',
\})
