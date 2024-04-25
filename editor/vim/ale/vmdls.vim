autocmd BufNewFile,BufRead *.mcl set filetype=mcl
autocmd BufNewFile,BufRead *.vmd set filetype=vmd

call ale#linter#Define('mcl', {
\   'name': 'mclls',
\   'lsp': 'stdio',
\   'executable': 'mclls',
\   'command': '%e --log-level debug --disable completion 2>log',
\   'project_root': '.',
\})

call ale#linter#Define('vmd', {
\   'name': 'mclls',
\   'lsp': 'stdio',
\   'executable': 'mclls',
\   'command': '%e --log-level debug --disable completion 2>log',
\   'project_root': '.',
\})
