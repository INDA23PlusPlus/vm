autocmd BufNewFile,BufRead *.mcl set filetype=mcl

call ale#linter#Define('mcl', {
\   'name': 'mclls',
\   'lsp': 'stdio',
\   'executable': '/home/ludviggl/dev/kth/vm/zig-out/bin/langserver',
\   'command': '%e',
\   'project_root': '.',
\})
