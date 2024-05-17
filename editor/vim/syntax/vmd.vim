syn iskeyword                   -,_,a-z,A-Z
syn match       VeModComment    "#.*$"
syn keyword     VeModKeyword    -function -begin -end -string
syn match       VeModString     '"\(\\n\|\\\\\|\\"\|\\e\|[^"\\]\|[\n\r]\)*"\?'
syn match       VeModIdentifier "\$[^ \t\r\n]*"
syn match       VeModLabel      "\.[^ \t\r\n]*"
syn match       VeModInt        "%[^ \t\r\n]*"
syn match       VeModFloat      "@[^ \t\r\n]*"
syn keyword     VeModOp         add sub mul neg div mod inc dec log_or log_and log_not bit_or bit_xor bit_and bit_not cmp_lt cmp_gt cmp_le cmp_ge cmp_eq cmp_ne jmp jmpnz push pushf pushs pop dup load store syscall call ret stack_alloc struct_alloc struct_load struct_store list_alloc list_load list_store list_length list_append list_pop list_remove list_concat
hi def link     VeModComment    Comment
hi def link     VeModKeyword    Keyword
hi def link     VeModString     String
hi def link     VeModIdentifier Identifier
hi def link     VeModLabel      Label
hi def link     VeModInt        Number
hi def link     VeModFloat      Number
hi def link     VeModOp         Function
