autocmd BufNewFile,BufRead *.mcl set filetype=mcl
autocmd BufNewFile,BufRead *.vmd set filetype=vmd

call ale#linter#Define('mcl', {
\   'name': 'mclls',
\   'lsp': 'stdio',
\   'executable': 'mclls',
\   'command': '%e 2>log',
\   'project_root': '.',
\})

call ale#linter#Define('vmd', {
\   'name': 'mclls',
\   'lsp': 'stdio',
\   'executable': 'mclls',
\   'command': '%e 2>log',
\   'project_root': '.',
\})
