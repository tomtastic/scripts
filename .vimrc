" This must be first, because it changes other options as side effect
set nocompatible

"set nowrap        " don't wrap lines
set tabstop=4     " a tab is four spaces
set shiftwidth=4  " number of spaces to use for autoindenting
set backspace=indent,eol,start
                  " allow backspacing over everything in insert mode
set autoindent    " always set autoindenting on
set copyindent    " copy the previous indentation on autoindenting
set shiftround    " use multiple of shiftwidth when indenting with '<' and '>'
set ignorecase    " ignore case when searching
set smartcase     " ignore case if search pattern is all lowercase,
                  "    case-sensitive otherwise
set smarttab      " insert tabs on the start of a line according to
                  "    shiftwidth, not tabstop
set hlsearch      " highlight search terms
set incsearch     " show search matches as you type
set history=1000         " remember more commands and search history
set undolevels=1000      " use many muchos levels of undo
set wildignore=*.swp,*.bak,*.pyc,*.class
set title                " change the terminal's title
let &titleold=hostname()
set titlestring=%t%(\ %M%)%(\ (%{expand(\"%:p:h\")})%)%(\ %a%)
"set titlestring=VIM:\ %F
set pastetoggle=<F2>
set visualbell           " don't beep
set noerrorbells         " don't beep
set nobackup
set noswapfile

if &term =~ "xterm"
     if has("terminfo")
        set t_Co=8
        set t_Sf=1%dm
        set t_Sb=1%dm
     else
        set t_Co=8
        set t_Sf=m
        set t_Sb=m
     endif
endif

syntax on
color torte

" dont use Q for Ex mode
map Q :q

" show matching brackets
autocmd FileType perl set showmatch

" show line numbers
autocmd FileType perl set number

" check perl code with :make
autocmd FileType perl set makeprg=perl\ -c\ %\ $*
autocmd FileType perl set errorformat=%f:%l:%m
autocmd FileType perl set autowrite

" syntax color complex things like @{${"foo"}}
let perl_extended_vars = 1
