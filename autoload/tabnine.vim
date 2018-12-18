if !exists('s:job')
    let s:job = 0
endif

function! s:isJobAlive() abort
    if s:job == 0
        return v:false
    endif
    try
        if jobpid(s:job)
            return v:true
        endif
    catch /E900/
    endtry
    return v:false
endfunction

function! s:getTabNineJob() abort
    if !s:isJobAlive()
        let l:jobArgs = [g:tabnine_executablePath]
        if exists('g:tabnine_logPath')
            call add(l:jobArgs, '--log-file-path')
            call add(l:jobArgs, g:tabnine_logPath)
        endif
        if exists('g:tabnine_logLevel')
            call add(l:jobArgs, '--log-level')
            call add(l:jobArgs, g:tabnine_logLevel)
        endif
        let s:job = jobstart(l:jobArgs, {
                    \ 'on_stdout': function('s:handleStdout')
                    \ })
    endif
    return s:job
endfunction

function! s:getBytes(fromByte, toByte) abort
    let l:firstLine = byte2line(a:fromByte)
    let l:startByteInLine = a:fromByte - line2byte(l:firstLine)
    let l:lastLine = byte2line(a:toByte)
    let l:endByteInLine = a:toByte - line2byte(l:lastLine)

    let l:result = getline(l:firstLine, l:lastLine)

    if l:endByteInLine <= 0
        let l:result[-1] = ''
    else
        let l:result[-1] = l:result[-1][:l:endByteInLine - 1]
    endif
    if 0 < l:startByteInLine
        let l:result[0] = l:result[0][l:startByteInLine:]
    endif

    return join(l:result, "\n")
endfunction

function! s:getParamsForCompletion(maxBytes)
    let l:curByte = line2byte('.') + col('.') - 1
    let l:lastByte = line2byte('$') + len(getline('$'))
    if l:lastByte < a:maxBytes
        return {
                    \ 'before': s:getBytes(1, l:curByte),
                    \ 'region_includes_beginning': v:true,
                    \ 'after': s:getBytes(l:curByte, l:lastByte),
                    \ 'region_includes_end': v:true}
    endif

    let l:result = {
                \ 'region_includes_beginning': v:false,
                \ 'region_includes_end': v:false}

    if l:curByte <= a:maxBytes / 2 + 1
        " Can take all the bytes before
        let l:result.region_includes_beginning = v:true
        let l:result.before = s:getBytes(1, l:curByte)
        let l:result.after = s:getBytes(l:curByte, l:curByte + a:maxBytes - len(l:result.before))
    elseif l:lastByte <= l:curByte + a:maxBytes / 2
        " Can take all the bytes after
        let l:result.region_includes_end = v:true
        let l:result.after = s:getBytes(l:curByte, l:lastByte)
        let l:result.before = s:getBytes(l:curByte - a:maxBytes + len(l:result.after), l:curByte)
    else
        " Should split them
        let l:result.before = s:getBytes(l:curByte - a:maxBytes / 2, l:curByte)
        let l:result.after = s:getBytes(l:curByte, l:curByte + a:maxBytes / 2)
    endif
    return l:result
endfunction

function! s:handleStdout(id, data, event) abort
    for l:data in a:data
        try
            let l:decoded = json_decode(l:data)
        catch
            continue
        endtry
        if has_key(l:decoded, 'results')
            if string(mode() !~ '\C\v^[iR]')
                continue
            end
            call complete(
                        \ col('.') - len(l:decoded.old_prefix),
                        \ map(l:decoded.results, 's:parseCompletion(v:val)'))
        endif
    endfor
endfunction

function! s:parseCompletion(completion) abort
    let l:item = {}
    let l:item.word = a:completion.new_prefix
    if has_key(a:completion, 'kind')
        let l:item.kind = a:completion.kind
    endif
    if has_key(a:completion, 'documentation')
        let l:item.info = a:completion.documentation
    endif
    if has_key(a:completion, 'detail')
        let l:item.menu = a:completion.detail
    endif
    if has_key(a:completion, 'deprecated')
        if has_key(l:item, 'menu')
            let l:item.menu = '[deprecated] ' . l:item.menu
        else
            let l:item.menu = '[deprecated']
        endif
    endif
    return l:item
endfunction

function! s:formatRequestMessage(request) abort
    return json_encode({"version": "1.0.0", "request": a:request})
endfunction

function! s:sendCommand(message, params) abort
    call chansend(s:getTabNineJob(), s:formatRequestMessage({a:message: a:params}))
    call chansend(s:getTabNineJob(), "\n")
endfunction

function! tabnine#complete(findstart, base) abort
    if a:findstart
        " Let TabNine decide
        return 0
    else
        let l:job = s:getTabNineJob()
        let l:params = s:getParamsForCompletion(100 * 1024)
        let l:params["filename"] = expand('%:p')
        call s:sendCommand("Autocomplete", l:params)
        return []
    endif
endfunction
