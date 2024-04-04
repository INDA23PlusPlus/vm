
syn keyword VeModKeyword -function -begin -end
syn match   VeModComment "#.*$"
syn match   VeModInt     "%\d\+"
syn match   VeModFloat   "@\d\+\.\d\+"
syn match   VeModLabel   ".[a-zA-Z_][a-zA-Z_0-9]*"
syn match   VeModString  '"[^"]*"'
hi def link VeModKeyword Keyword
hi def link VeModComment Comment
hi def link VeModInt     Number
hi def link VeModFloat   Number
hi def link VeModLabel   Identifier
hi def link VeModString  String
