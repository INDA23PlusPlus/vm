autocmd BufNewFile,BufRead *.mcl set filetype=mcl
autocmd BufNewFile,BufRead *.vmd set filetype=vmd

call ale#linter#Define('mcl', {
\   'name': 'mclls',
\   'lsp': 'stdio',
\   'executable': '../../../zig-out/bin/langserver',
\   'command': '%e --log-file mclls.log --log-output file',
\   'project_root': '.',
\})

call ale#linter#Define('vmd', {
\   'name': 'mclls',
\   'lsp': 'stdio',
\   'executable': '../../../zig-out/bin/langserver',
\   'command': '%e --log-file mclls.log --log-output file',
\   'project_root': '.',
\})
