autocmd BufNewFile,BufRead *.mcl set filetype=melancolang
autocmd BufNewFile,BufRead *.vmd set filetype=vemod
autocmd BufNewFile,BufRead *.blue set filetype=blue

call ale#linter#Define('melancolang', {
\   'name': 'vmdls',
\   'lsp': 'stdio',
\   'executable': 'vmdls',
\   'command': '%e',
\   'project_root': '.',
\})

call ale#linter#Define('vemod', {
\   'name': 'vmdls',
\   'lsp': 'stdio',
\   'executable': 'vmdls',
\   'command': '%e',
\   'project_root': '.',
\})

call ale#linter#Define('blue', {
\   'name': 'vmdls',
\   'lsp': 'stdio',
\   'executable': 'vmdls',
\   'command': '%e',
\   'project_root': '.',
\})
