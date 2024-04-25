autocmd BufNewFile,BufRead *.mcl set filetype=mcl
autocmd BufNewFile,BufRead *.vmd set filetype=vmd

call ale#linter#Define('mcl', {
\   'name': 'vmdls',
\   'lsp': 'stdio',
\   'executable': 'vmdls',
\   'command': '%e',
\   'project_root': '.',
\})

call ale#linter#Define('vmd', {
\   'name': 'vmdls',
\   'lsp': 'stdio',
\   'executable': 'vmdls',
\   'command': '%e',
\   'project_root': '.',
\})
