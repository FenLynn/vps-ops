" vps-ops Vim Configuration
set nocompatible
filetype plugin indent on
syntax on

" UI & Layout
set number
set relativenumber
set cursorline
set showmatch
set laststatus=2

" Indentation
set expandtab
set shiftwidth=4
set tabstop=4
set softtabstop=4
set autoindent
set smartindent

" Search
set hlsearch
set incsearch
set ignorecase
set smartcase

" Behavior
set mouse=a
set clipboard=unnamedplus
set encoding=utf-8
set hidden
set history=1000

" Disable backup/swap for simpler ops
set nobackup
set nowritebackup
set noswapfile
