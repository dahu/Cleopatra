"" ============================================================================
" File:        Cleopatra.vim
" Description: A hierarchical marks manager with treeview
" Authors:     Barry Arthur <barry dot arthur at gmail dot com>
"              Israel Chauca <israelchauca at gmail dot com>
" Licence:     Vim licence
" Website:     http://dahu.github.com/Cleopatra/
" Version:     0.1
" Note:        This plugin was heavily inspired by the 'Tagbar' plugin by
"              Jan Larres and uses great gobs of code from it.
"
" Original taglist copyright notice:
"              Permission is hereby granted to use and distribute this code,
"              with or without modifications, provided that this copyright
"              notice is copied with it. Like anything else that's free,
"              taglist.vim is provided *as is* and comes with no warranty of
"              any kind, either expressed or implied. In no event will the
"              copyright holder be liable for any damamges resulting from the
"              use of this software.
" ============================================================================

if &cp || exists('g:loaded_cleopatra')
  finish
endif

" Initialization {{{1

" Basic init {{{2

if v:version < 700
  echomsg 'Cleopatra: Vim version is too old, Cleopatra requires at least 7.0'
  finish
endif

redir => s:ftype_out
silent filetype
redir END
if s:ftype_out !~# 'detection:ON'
  echomsg 'Cleopatra: Filetype detection is turned off, skipping plugin'
  unlet s:ftype_out
  finish
endif
unlet s:ftype_out

let g:loaded_cleopatra = 1

if !exists('g:cleopatra_left')
  let g:cleopatra_left = 0
endif

if !exists('g:cleopatra_width')
  let g:cleopatra_width = 20
endif

if !exists('g:cleopatra_autoclose')
  let g:cleopatra_autoclose = 0
endif

if !exists('g:cleopatra_compact')
    let g:cleopatra_compact = 0
endif

if !exists('g:cleopatra_expand')
  let g:cleopatra_expand = 0
endif

let s:snippets_init_done    = 0
let s:autocommands_done     = 0
let s:window_expanded       = 0
let s:snippets              = []

" From :help <SID>
function s:SID()
  return matchstr(expand('<sfile>'), '<SNR>\d\+_\zeSID$')
endfun

let s:engines = {
      \ 'snipmate': {
      \   'detect': 'exists("g:loaded_snips")',
      \   'list_func': 'snipMate#GetSnippetsForWordBelowCursor',
      \   'list_func_args': 'a:word,"*",0',
      \   'list_map': 'v:val[0]'
      \   },
      \ 'xptemplate': {
      \   'detect': 'exists(''g:__XPTEMPLATE_VIM__'')',
      \   'list_func': s:SID().'xptemplate_helper',
      \   'list_func_args': 'a:word'
      \   },
      \ 'ultisnips': {
      \   'detect': 'exists(''g:did_UltiSnips_vim'')',
      \   'list_func': s:SID().'ultisnips_helper',
      \   'list_func_args': 'a:word'
      \   }
      \ }

" TODO: Should we allow only one engine?
if exists('g:cleopatra_engines')
  " Add extra entries
  call extend(s:engines, g:cleopatra_engines, 'keep')
  " Merge common entries
  call map(s:engines,
        \ 'has_key(g:cleopatra_engines, v:key)'.
        \ '? extend(s:engines[v:key], g:cleopatra_engines[v:key], "force")'.
        \ ': v:val')
endif

" s:CreateAutocommands() {{{2
function! s:CreateAutocommands()
    augroup CleopatraAutoCmds
        autocmd!
        autocmd BufEnter   __Cleopatra__ nested
              \ call s:QuitIfOnlyWindow()
        autocmd BufUnload  __Cleopatra__
              \ call s:CleanUp()
        autocmd FileType   *
              \ unlet! b:did_xpt
        autocmd CursorMovedI *
              \ call s:AutoUpdate()
    augroup END

    let s:autocommands_done = 1
endfunction

" s:MapKeys() {{{2
function! s:MapKeys()
  "nnoremap <script> <silent> <buffer> <CR>
        "\ :call <SID>InsertSnippet()<CR>
  "nnoremap <script> <silent> <buffer> <2-LeftMouse>
        "\ :call <SID>InsertSnippet()<CR>
  "nnoremap <script> <silent> <buffer> <LeftRelease> <LeftRelease>
        "\ :call <SID>CheckMouseClick()<CR>
  "nnoremap <script> <silent> <buffer> <Space>
        "\ :call <SID>ShowSnippetExpansion()<CR>

  nnoremap <script> <silent> <buffer> q    :call <SID>CloseWindow()<CR>
endfunction


" Window management {{{1
" Window management code shamelessly stolen from the Tagbar plugin:
" http://www.vim.org/scripts/script.php?script_id=3465

" s:ToggleWindow() {{{2
function! s:ToggleWindow()
  let cleopatrawinnr = bufwinnr("__Cleopatra__")
  if cleopatrawinnr != -1
    call s:CloseWindow()
    return
  endif

  call s:OpenWindow(0)
endfunction

" s:OpenWindow() {{{2
function! s:OpenWindow(autoclose)
  call s:set_engine()
  if !exists('s:engine')
    " XXX There is nothing to show.
    echohl ErrorMsg
    echom 'Cleopatra could not find a snippets engine!'
    echohl None
    return
  endif
  " If the cleopatra window is already open jump to it
  let cleopatrawinnr = bufwinnr('__Cleopatra__')
  if cleopatrawinnr != -1
    if winnr() != cleopatrawinnr
      execute cleopatrawinnr . 'wincmd w'
    endif
    return
  endif

  " Expand the Vim window to accomodate for the Cleopatra window if requested
  if g:cleopatra_expand && !s:window_expanded && has('gui_running')
    let &columns += g:cleopatra_width + 1
    let s:window_expanded = 1
  endif

  let openpos = g:cleopatra_left ? 'topleft vertical ' : 'botright vertical '
  exe 'silent keepalt ' . openpos . g:cleopatra_width . 'split ' . '__Cleopatra__'

  call s:InitWindow(a:autoclose)

  execute 'wincmd p'

  "" Jump back to the cleopatra window if autoclose or autofocus is set. Can't
  "" just stay in it since it wouldn't trigger the update event
  "if g:cleopatra_autoclose || a:autoclose || g:cleopatra_autofocus
  "let cleopatrawinnr = bufwinnr('__Cleopatra__')
  "execute cleopatrawinnr . 'wincmd w'
  "endif
endfunction

" s:InitWindow() {{{2
function! s:InitWindow(autoclose)
  setlocal noreadonly " in case the "view" mode is used
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal noswapfile
  setlocal nobuflisted
  setlocal nomodifiable
  setlocal filetype=cleopatra
  setlocal nolist
  setlocal nonumber
  setlocal nowrap
  setlocal winfixwidth
  setlocal textwidth=0

  if exists('+relativenumber')
    setlocal norelativenumber
  endif

  setlocal nofoldenable
  setlocal foldcolumn=0
  " Reset fold settings in case a plugin set them globally to something
  " expensive. Apparently 'foldexpr' gets executed even if 'foldenable' is
  " off, and then for every appended line (like with :put).
  setlocal foldmethod&
  setlocal foldexpr&

  "setlocal statusline=%!CleopatraGenerateStatusline()

  " Script-local variable needed since compare functions can't
  " take extra arguments
  let s:compare_typeinfo = {}

  let s:is_maximized = 0

  let w:autoclose = a:autoclose

  let cpoptions_save = &cpoptions
  set cpoptions&vim

  if !hasmapto('CloseWindow', 'n')
    call s:MapKeys()
  endif

  if !s:autocommands_done
    call s:CreateAutocommands()
  endif

  let &cpoptions = cpoptions_save
endfunction

" s:CloseWindow() {{{2
function! s:CloseWindow()
  let cleopatrawinnr = bufwinnr('__Cleopatra__')
  if cleopatrawinnr == -1
    return
  endif

  let cleopatrabufnr = winbufnr(cleopatrawinnr)

  if winnr() == cleopatrawinnr
    if winbufnr(2) != -1
      " Other windows are open, only close the cleopatra one
      close
    endif
  else
    " Go to the cleopatra window, close it and then come back to the
    " original window
    let curbufnr = bufnr('%')
    execute cleopatrawinnr . 'wincmd w'
    close
    " Need to jump back to the original window only if we are not
    " already in that window
    let winnum = bufwinnr(curbufnr)
    if winnr() != winnum
      exe winnum . 'wincmd w'
    endif
  endif

  " If the Vim window has been expanded, and Cleopatra is not open in any other
  " tabpages, shrink the window again
  if s:window_expanded
    let tablist = []
    for i in range(tabpagenr('$'))
      call extend(tablist, tabpagebuflist(i + 1))
    endfor

    if index(tablist, cleopatrabufnr) == -1
      let &columns -= g:cleopatra_width + 1
      let s:window_expanded = 0
    endif
  endif
endfunction

" s:ZoomWindow() {{{2
function! s:ZoomWindow()
  if s:is_maximized
    execute 'vert resize ' . g:cleopatra_width
    let s:is_maximized = 0
  else
    vert resize
    let s:is_maximized = 1
  endif
endfunction


" Display {{{1
" s:RenderContent() {{{2
function! s:RenderContent(word)
  let cleopatrawinnr = bufwinnr('__Cleopatra__')

  if &filetype == 'cleopatra'
    let in_cleopatra = 1
  else
    let in_cleopatra = 0
    let prevwinnr = winnr()
    execute cleopatrawinnr . 'wincmd w'
  endif

  let lazyredraw_save = &lazyredraw
  set lazyredraw
  let eventignore_save = &eventignore
  set eventignore=all

  setlocal modifiable

  silent %delete _

  call s:PrintSnippets()

  setlocal nomodifiable

 " Do we need this?
  execute 1
  call winline()

  let &lazyredraw  = lazyredraw_save
  let &eventignore = eventignore_save

  if !in_cleopatra
    execute prevwinnr . 'wincmd w'
  endif
endfunction

" s:PrintSnippets {{{2
function! s:PrintSnippets()
  silent put =s:snippets
endfunction

"
" User Actions {{{1

" Helper Functions {{{1

" s:ultisnips_helper() {{{2
function! s:ultisnips_helper(word)
  exec "py vim.command('let snippets = \\'' + str(UltiSnips_Manager._snips('".a:word."', True)) + '\\'')"
  let snippets = substitute(snippets, 'Snippet(\([^,]\+\)\%("\%(\\.\|[^\\"]\)*"\|[^"]\)\{-})\(,\s*\)\?','\1\2', 'g')
  return sort(split(snippets[1:-2],',\s*'))
endfunction

" s:xptemplate_helper() {{{2
function! s:xptemplate_helper(word)
  if !exists('b:did_xpt')
    call XPTparseSnippets()
    let b:did_xpt = 1
  endif
  return sort(filter(keys(b:xptemplateData.filetypes[&filetype].allTemplates), 'v:val !~ ''\W\|^_'' && v:val =~? "^".a:word'))
endfunction

" s:set_engine() {{{2
function! s:set_engine()
  if exists('g:cleopatra_engine')
    let s:engine = s:engines[tolower(g:cleopatra_engine)]
  else
    for key in keys(s:engines)
      if eval(s:engines[key].detect)
        let s:engine = s:engines[key]
        let s:engine.name = key
        break
      endif
    endfor
  endif
  if !exists('s:engine')
    "TODO: What to do here?
    echohl ErrorMsg
    echom 'Cleopatra: No snippet engine was found!'
    echohl None
  else
    if !has_key(s:engine, 'pattern')
      let s:engine.pattern = '\W\zs\w\+\%#'
    endif
    if !has_key(s:engine, 'list_func_args')
      let s:engine.list_func_args = ''
    endif
  endif
endfunction

" s:CleanUp() {{{2
function! s:CleanUp()
    silent autocmd! CleopatraAutoCmds

    unlet s:is_maximized
    unlet s:compare_typeinfo
endfunction

" s:QuitIfOnlyWindow() {{{2
function! s:QuitIfOnlyWindow()
    " Before quitting Vim, delete the cleopatra buffer so that
    " the '0 mark is correctly set to the previous buffer.
    if winbufnr(2) == -1
        " Check if there is more than one tab page
        if tabpagenr('$') == 1
            bdelete
            quit
        else
            close
        endif
    endif
endfunction

" s:AutoUpdate() {{{2
function! s:AutoUpdate()
  " Don't do anything if cleopatra is not open or if we're in the cleopatra window
  let cleopatrawinnr = bufwinnr('__Cleopatra__')
  if cleopatrawinnr == -1 || &filetype == 'cleopatra'
    return
  endif

  let p = searchpos(s:engine.pattern, 'bnW')
  let word = strpart(getline('.'), p[1]-1, col('.')-p[1])
  call s:Snippets(word)

  call s:RenderContent(word)
endfunction

" s:Snippets(word) {{{2
function! s:Snippets(word)
  let args = eval('['.s:engine.list_func_args.']')
  let s:snippets = call(s:engine.list_func, args)
  if has_key(s:engine, 'list_map')
    call map(s:snippets, s:engine.list_map)
    "echom 'map'
  endif
endfunction

" Commands {{{1
command! -nargs=0 CleopatraToggle        call s:ToggleWindow()
command! -nargs=0 CleopatraOpen          call s:OpenWindow(0)
command! -nargs=0 CleopatraOpenAutoClose call s:OpenWindow(1)
command! -nargs=0 CleopatraClose         call s:CloseWindow()

" Modeline {{{1
" vim: ts=8 sw=2 sts=2 et foldenable foldmethod=marker foldcolumn=1
