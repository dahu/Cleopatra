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
  " echomsg 'Cleopatra: Filetype detection is turned off, skipping plugin'
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

if !exists('g:cleopatra_minify')
    let g:cleopatra_minify = 1
endif

if !exists('g:cleopatra_expand')
  let g:cleopatra_expand = 0
endif

" TODO: check if we have vimple
let s:vimple_init_done         = 0
let s:autocommands_done        = 0
let s:source_autocommands_done = 0
let s:window_expanded          = 0


" Sort the vimple#marks by line number
function! Linely(i, j)
  let i = str2nr(a:i.line)
  let j = str2nr(a:j.line)
  return i == j ? 0 : i > j ? 1 : -1
endfunction

let s:mark_placement = {
      \ 'outer'  : '%s  ',
      \ 'middle' : ' %s ',
      \ 'inner'  : '  %s'}

" TODO: these need to be updated as the user issues
" :CleoMark <outer|middle|inner> on lines within the buffer.
" TODO: what marks a buffer considres to be in those three sets needs to be
" persisted

let s:mark_hierarchy = {
      \ 'outer'  : 'qwerty',
      \ 'middle' : 'asdfghjkl',
      \ 'inner'  : 'zxcvbnmuiop'}

function! CleoMarkHiercharchy(mark)
  return printf(
        \ s:mark_placement[keys(
        \   filter(copy(s:mark_hierarchy), 'v:val =~ "' . a:mark . '"')
        \ )[0]],
        \ a:mark)
endfunction

function! Numerically(i1, i2)
  return a:i1 - a:i2
endfunction

function! CleoMarks(cursor_line)
  let marks = g:vimple#ma.update().local_marks().to_l()
  " Locate the cursor line within the marks
  " 1. does it fall on a mark?
  call map(marks, 'v:val["line"] == ' . a:cursor_line . ' ? extend(v:val, {"cursor" : ""}) : v:val')
  if len(filter(copy(marks), 'has_key(v:val, "cursor")')) == 0
    " 2. where does it fall between marks?
    " 0  == before all marks
    " -1 == after all marks
    " positive integer == the index of the cursor line
    if len(marks) == 0
      let cursor_index = 0
    else
      let cursor_index = index(map(sort(map(copy(marks), 'v:val["line"]'), 'Numerically'),
            \ 'v:val == min([v:val,' . a:cursor_line . '])'), 0)
    endif
    call insert(marks,
          \ {'cursor' : '', 'line' : a:cursor_line, 'mark' : '', 'text' : ''},
          \ cursor_index)
  endif
  return map(sort(marks, 'Linely'),
        \ 'printf("%1s %3s %4d %s", has_key(v:val, "cursor") ? "*" : "",
        \ CleoMarkHiercharchy(v:val["mark"]),
        \ v:val["line"], s:MinifyText(v:val["text"]))')
endfunction

function! s:MinifyText(text)
  let available_width = g:cleopatra_width - 10
  let excess = available_width - len(a:text)
  if (! g:cleopatra_minify) || (excess > 0)
    return a:text
  endif
  let portion = available_width / len(split(a:text, '\W\+\|\s\+'))
  let text = substitute(a:text
        \ , '\C\<\([a-z]\{' . portion . '\}\)[a-zA-Z0-9_]\+', '\1', 'g')
  let text = substitute(text
        \ , '\C[A-Z]\zs[a-z0-9_]\+', '', 'g')
  return text
endfunction

" s:CreateAutocommands() {{{2
function! s:CreateAutocommands()
  augroup CleopatraAutoCmds
    autocmd!
    autocmd BufEnter   __Cleopatra__ nested
          \ call s:QuitIfOnlyWindow()
    autocmd BufUnload  __Cleopatra__
          \ call s:CleanUp()
    autocmd CursorMoved __Cleopatra__
          \ call s:AutoUpdate()
  augroup END

  let s:autocommands_done = 1
endfunction

" s:CreateSourceAutocommands() {{{2
function! s:CreateSourceAutocommands()
  augroup CleopatraSourceAutoCmds
    autocmd!
    autocmd CursorMoved <buffer>
          \ call s:SourceAutoUpdate()
  augroup END
  let s:source_autocommands_done = 1
endfunction

" s:MapKeys() {{{2
function! s:MapKeys()
  nnoremap <script> <silent> <buffer> <CR> :wincmd p<cr>
  nnoremap <script> <silent> <buffer> m    :call <SID>ToggleMinify()<CR>
  nnoremap <script> <silent> <buffer> q    :call <SID>CloseWindow()<CR>
endfunction

" TODO: Currently only reflects toggle after leaving & entering Cleo window
function! s:ToggleMinify()
  let g:cleopatra_minify = !g:cleopatra_minify
  call s:RenderContent()
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
  " If the cleopatra window is already open jump to it
  let cleopatrawinnr = bufwinnr('__Cleopatra__')
  if cleopatrawinnr != -1
    if winnr() != cleopatrawinnr
      let t:cleo_marks = CleoMarks(line('.'))
      execute cleopatrawinnr . 'wincmd w'
    endif
    return
  else
    let t:cleo_marks = CleoMarks(line('.'))
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

  " TODO: need a better name for this, or a better way to do it
  if !s:source_autocommands_done
    call s:CreateSourceAutocommands()
  endif

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

  call s:RenderContent()

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
function! s:RenderContent()
  " only update the Cleopatra window if we're in normal mode
  if mode(1) != 'n'
    return
  endif
  let cleopatrawinnr = bufwinnr('__Cleopatra__')

  if &filetype == 'cleopatra'
    let in_cleopatra = 1
  else
    let in_cleopatra = 0
    let t:cleo_marks = CleoMarks(line('.'))
    let prevwinnr = winnr()
    execute cleopatrawinnr . 'wincmd w'
  endif

  let lazyredraw_save = &lazyredraw
  set lazyredraw
  let eventignore_save = &eventignore
  set eventignore=all

  setlocal modifiable

  silent %delete _

  call s:PrintMarks()

  setlocal nomodifiable

  " Open Cleo window with cursor on paired window's current line
  1
  call search('^\*')

  let &lazyredraw  = lazyredraw_save
  let &eventignore = eventignore_save

  if !in_cleopatra
    execute prevwinnr . 'wincmd w'
  endif
endfunction

" s:PrintMarks {{{2
function! s:PrintMarks()
  call setline(1, t:cleo_marks)
endfunction

"
" User Actions {{{1

" Helper Functions {{{1

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

" TODO: This needs to update the source window to reflect the current cursor
" position within the Cleopatra window
" s:AutoUpdate() {{{2
function! s:AutoUpdate()
  " Don't do anything if cleopatra is not open or if we're in the cleopatra window
  let cleopatrawinnr = bufwinnr('__Cleopatra__')
  if cleopatrawinnr == -1
    return
  endif
  if &filetype == 'cleopatra'
    let line = getline('.')
    let line_num = matchstr(line, ' \zs\d\+')
    wincmd p
    exe 'normal ' . line_num . 'Gzz'
    redraw
    wincmd p
  else
    call s:RenderContent()
  endif
endfunction

" s:SourceAutoUpdate() {{{2
function! s:SourceAutoUpdate()
  " Don't do anything if cleopatra is not open or if we're in the cleopatra window
  let cleopatrawinnr = bufwinnr('__Cleopatra__')
  if cleopatrawinnr == -1 || &filetype == 'cleopatra'
    return
  endif

  call s:RenderContent()
endfunction

" Maps {{{1
nnoremap <leader>cc :CleopatraToggle<CR>:wincmd p<CR>

" Commands {{{1
command! -nargs=0 CleopatraToggle        call s:ToggleWindow()
command! -nargs=0 CleopatraOpen          call s:OpenWindow(0)
command! -nargs=0 CleopatraOpenAutoClose call s:OpenWindow(1)
command! -nargs=0 CleopatraClose         call s:CloseWindow()
" TODO: add complete="outer,middle,inner"
command! -nargs=1 CleopatraMarkLine      call s:CleoMarkLine(<q-args>)
command! -nargs=0 CleopatraUnmarkLine    call s:CleoUnmarkLine()

" Modeline {{{1
" vim: ts=8 sw=2 sts=2 et foldenable foldmethod=marker foldcolumn=1
