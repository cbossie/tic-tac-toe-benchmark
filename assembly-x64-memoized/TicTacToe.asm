; Hand-written x64 assembly (MASM) port of csharp-memoized/TicTacToeFast.cs: bitboards, a win lookup table and a
; memoised solver. No C runtime and no .NET: it talks to Windows through kernel32 only.
;
;   buildasm.ps1 builds it, or by hand from an x64 Native Tools prompt:
;     ml64 /nologo /c /Fo TicTacToeAsm.obj TicTacToe.asm
;     link /nologo /SUBSYSTEM:CONSOLE /ENTRY:main /NODEFAULTLIB /OUT:TicTacToeAsm.exe TicTacToeAsm.obj kernel32.lib
;
; Conventions: Win64 (rcx, rdx, r8, r9; rbx rsi rdi r12-r15 preserved). Positions are two 9-bit
; masks, bit i = square i+1. A position's value is for the side to move; a win k plies away is
; 10 - k, exactly as in the other versions.

extern GetStdHandle:proc
extern WriteFile:proc
extern ReadFile:proc
extern ExitProcess:proc
extern QueryPerformanceCounter:proc
extern QueryPerformanceFrequency:proc
extern GetCommandLineA:proc

.data
lines     DWORD 7, 56, 448, 73, 146, 292, 273, 84            ; rows, columns, diagonals
rng       QWORD 88172645463325252
outlen    DWORD 0

sTitle    BYTE "Tic-Tac-Toe: you are X, computer is O.", 10, 0
sYouFirst BYTE 10, "You go first.", 10, 0
sCompFst  BYTE 10, "Computer goes first.", 10, 0
sCompPlay BYTE 10, "Computer plays ", 0
sDotNL    BYTE ".", 10, 0
sNL       BYTE 10, 0
sSep      BYTE "---+---+---", 10, 0
sSp       BYTE " ", 0
sBar      BYTE " | ", 0
sRowEnd   BYTE " ", 10, 0
sPrompt   BYTE "Your move (1-9): ", 0
sBad      BYTE "Pick an empty square numbered 1-9.", 10, 0
sYouWin   BYTE "You win!", 10, 0
sCompWin  BYTE "Computer wins!", 10, 0
sDraw     BYTE "It's a draw.", 10, 0
sAgain    BYTE 10, "Play again? (y/n): ", 0
sBench    BYTE "--bench", 0
sFirst    BYTE "first pass : ", 0
sLater    BYTE "later passes: ", 0
sNs       BYTE " ns/move", 10, 0

.data?
hOut      QWORD ?
hIn       QWORD ?
written   DWORD ?
nread     DWORD ?
byteBuf   BYTE ?
linebuf   BYTE 64 dup (?)
wins      BYTE 512 dup (?)                  ; wins[mask] = 1 when mask contains a line
cache     BYTE 262144 dup (?)               ; value + 11 per (mover | other << 9); 0 = unknown
outbuf    BYTE 4096 dup (?)
qpcFreq   QWORD ?
tStart    QWORD ?
tEnd      QWORD ?
tCold     QWORD ?

.code

; ---------------------------------------------------------------- output
Flush proc
    mov     eax, outlen
    test    eax, eax
    jz      done
    sub     rsp, 56
    mov     rcx, hOut
    lea     rdx, outbuf
    mov     r8d, eax
    lea     r9, written
    mov     qword ptr [rsp+32], 0
    call    WriteFile
    mov     outlen, 0
    add     rsp, 56
done:
    ret
Flush endp

PutChar proc                                ; cl = character; clobbers rax, rdx
    mov     eax, outlen
    lea     rdx, outbuf
    mov     [rdx+rax], cl
    inc     eax
    mov     outlen, eax
    ret
PutChar endp

PutStr proc                                 ; rcx = zero-terminated string; clobbers rax, rdx, r8
    lea     r8, outbuf
    mov     eax, outlen
next:
    mov     dl, [rcx]
    test    dl, dl
    jz      done
    mov     [r8+rax], dl
    inc     rax
    inc     rcx
    jmp     next
done:
    mov     outlen, eax
    ret
PutStr endp

PutUInt proc                                ; rcx = unsigned value, printed in decimal
    push    rbx
    push    rsi
    sub     rsp, 24
    mov     rax, rcx
    lea     rsi, [rsp+23]
    xor     ebx, ebx
    mov     r9d, 10
digit:
    xor     edx, edx
    div     r9
    add     dl, '0'
    mov     [rsi], dl
    dec     rsi
    inc     ebx
    test    rax, rax
    jnz     digit
emit:
    inc     rsi
    movzx   ecx, byte ptr [rsi]
    call    PutChar
    dec     ebx
    jnz     emit
    add     rsp, 24
    pop     rsi
    pop     rbx
    ret
PutUInt endp

; ---------------------------------------------------------------- input
; Reads one line from stdin into linebuf (spaces, tabs and CR dropped, zero-terminated).
; Returns its length, or -1 at end of input.
ReadLine proc
    push    rbx
    push    rsi
    sub     rsp, 56
    call    Flush
    xor     esi, esi
more:
    mov     rcx, hIn
    lea     rdx, byteBuf
    mov     r8d, 1
    lea     r9, nread
    mov     qword ptr [rsp+32], 0
    call    ReadFile
    test    eax, eax
    jz      eof
    cmp     nread, 0
    je      eof
    movzx   eax, byteBuf
    cmp     al, 10
    je      done
    cmp     al, 13
    je      more
    cmp     al, 32
    je      more
    cmp     al, 9
    je      more
    cmp     esi, 62
    jae     more
    lea     rdx, linebuf
    mov     [rdx+rsi], al
    inc     esi
    jmp     more
eof:
    test    esi, esi
    jnz     done
    mov     eax, -1
    jmp     quitp
done:
    lea     rdx, linebuf
    mov     byte ptr [rdx+rsi], 0
    mov     eax, esi
quitp:
    add     rsp, 56
    pop     rsi
    pop     rbx
    ret
ReadLine endp

; ---------------------------------------------------------------- random numbers
RandBelow proc                              ; ecx = n; returns eax in [0, n); xorshift64
    lea     r8, rng
    mov     rax, [r8]
    mov     rdx, rax
    shl     rdx, 13
    xor     rax, rdx
    mov     rdx, rax
    shr     rdx, 7
    xor     rax, rdx
    mov     rdx, rax
    shl     rdx, 17
    xor     rax, rdx
    mov     [r8], rax
    shr     rax, 32                         ; top 32 bits, scaled into [0, n)
    imul    rax, rcx
    shr     rax, 32
    ret
RandBelow endp

; ---------------------------------------------------------------- solver
; ecx = mover (side to move), edx = other (side that just moved); returns the value in eax.
Value proc
    lea     r8, wins
    cmp     byte ptr [r8+rdx], 0
    je      notlost
    mov     eax, -10
    ret
notlost:
    mov     eax, ecx
    or      eax, edx
    cmp     eax, 511
    jne     notfull
    xor     eax, eax
    ret
notfull:
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    mov     r12d, ecx                       ; mover
    mov     r13d, edx                       ; other
    mov     ebx, edx                        ; key = mover | other << 9
    shl     ebx, 9
    or      ebx, ecx
    lea     r8, cache
    movzx   eax, byte ptr [r8+rbx]
    test    eax, eax
    jz      compute
    sub     eax, 11
    jmp     quitp
compute:
    mov     edi, -11                        ; best
    mov     esi, r12d                       ; free squares
    or      esi, r13d
    not     esi
    and     esi, 511
movelp:
    test    esi, esi
    jz      store
    mov     eax, esi                        ; lowest free square
    neg     eax
    and     eax, esi
    xor     esi, eax
    mov     edx, r12d                       ; Value(other, mover | bit)
    or      edx, eax
    mov     ecx, r13d
    call    Value
    neg     eax                             ; Toward(-score): one ply further from the end
    test    eax, eax
    jg      shrinkpos
    jl      shrinkneg
    jmp     compare
shrinkpos:
    dec     eax
    jmp     compare
shrinkneg:
    inc     eax
compare:
    cmp     eax, edi
    jle     movelp
    mov     edi, eax
    jmp     movelp
store:
    lea     r8, cache
    lea     eax, [rdi+11]
    mov     [r8+rbx], al
    mov     eax, edi
quitp:
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
Value endp

; ecx = human squares, edx = computer squares; returns the computer's move (0-8) in eax.
ComputerMove proc
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, ecx
    mov     r13d, edx
    mov     eax, ecx
    or      eax, edx
    jnz     search
    mov     ecx, 9                          ; every opening draws, so skip the search
    call    RandBelow
    jmp     quitp
search:
    mov     r14d, 80000000h                 ; best score so far
    xor     r15d, r15d                      ; bitboard of the best moves
    mov     esi, r12d
    or      esi, r13d
    not     esi
    and     esi, 511
movelp:
    test    esi, esi
    jz      pick
    mov     ebx, esi
    neg     ebx
    and     ebx, esi
    xor     esi, ebx
    mov     edx, r13d                       ; Value(human, computer | bit)
    or      edx, ebx
    mov     ecx, r12d
    call    Value
    neg     eax
    test    eax, eax
    jg      shrinkpos
    jl      shrinkneg
    jmp     compare
shrinkpos:
    dec     eax
    jmp     compare
shrinkneg:
    inc     eax
compare:
    cmp     eax, r14d
    jg      better
    jl      movelp
    or      r15d, ebx
    jmp     movelp
better:
    mov     r14d, eax
    mov     r15d, ebx
    jmp     movelp
pick:
    popcnt  ecx, r15d                       ; choose uniformly among the best moves
    call    RandBelow
    mov     ecx, eax
dropbit:
    test    ecx, ecx
    jz      dropped
    lea     eax, [r15-1]
    and     r15d, eax
    dec     ecx
    jmp     dropbit
dropped:
    bsf     eax, r15d
quitp:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
ComputerMove endp

; ---------------------------------------------------------------- game
Sq proc                                     ; ecx = human, edx = computer, r8d = square; returns al
    bt      ecx, r8d
    jnc     notx
    mov     al, 'X'
    ret
notx:
    bt      edx, r8d
    jnc     noto
    mov     al, 'O'
    ret
noto:
    lea     eax, [r8+'1']
    ret
Sq endp

SQUARE macro col
    mov     ecx, r12d
    mov     edx, esi
    lea     r8d, [rbx+rbx*2+col]
    call    Sq
    movzx   ecx, al
    call    PutChar
endm

Render proc                                 ; ecx = human, edx = computer
    push    rbx
    push    rsi
    push    r12
    mov     r12d, ecx
    mov     esi, edx
    lea     rcx, sNL
    call    PutStr
    xor     ebx, ebx
row:
    cmp     ebx, 3
    jae     done
    test    ebx, ebx
    jz      nosep
    lea     rcx, sSep
    call    PutStr
nosep:
    lea     rcx, sSp
    call    PutStr
    SQUARE  0
    lea     rcx, sBar
    call    PutStr
    SQUARE  1
    lea     rcx, sBar
    call    PutStr
    SQUARE  2
    lea     rcx, sRowEnd
    call    PutStr
    inc     ebx
    jmp     row
done:
    lea     rcx, sNL
    call    PutStr
    pop     r12
    pop     rsi
    pop     rbx
    ret
Render endp

AskHumanMove proc                           ; ecx = occupied squares; returns 0-8
    push    rbx
    push    rsi
    push    rdi
    mov     ebx, ecx
ask:
    lea     rcx, sPrompt
    call    PutStr
    call    ReadLine
    cmp     eax, -1
    jne     have
    call    Flush                           ; input closed
    xor     ecx, ecx
    call    ExitProcess
have:
    cmp     eax, 1
    jne     bad
    movzx   eax, linebuf
    sub     eax, '1'
    cmp     eax, 8
    ja      bad
    bt      ebx, eax
    jc      bad
    pop     rdi
    pop     rsi
    pop     rbx
    ret
bad:
    lea     rcx, sBad
    call    PutStr
    jmp     ask
AskHumanMove endp

PlayGame proc
    push    rbx
    push    rsi
    push    rdi
    push    r12                             ; human squares
    push    r13                             ; computer squares
    push    r14                             ; 1 when it is the human's turn
    push    r15
    xor     r12d, r12d
    xor     r13d, r13d
    mov     ecx, 2
    call    RandBelow
    test    eax, eax
    jnz     compfirst
    lea     rcx, sYouFirst
    call    PutStr
    xor     ecx, ecx
    xor     edx, edx
    call    Render
    mov     r14d, 1
    jmp     turn
compfirst:
    lea     rcx, sCompFst
    call    PutStr
    xor     r14d, r14d
turn:
    test    r14d, r14d
    jz      computer
    mov     ecx, r12d
    or      ecx, r13d
    call    AskHumanMove
    bts     r12d, eax
    jmp     show
computer:
    mov     ecx, r12d
    mov     edx, r13d
    call    ComputerMove
    mov     r15d, eax
    bts     r13d, eax
    lea     rcx, sCompPlay
    call    PutStr
    lea     ecx, [r15+'1']
    call    PutChar
    lea     rcx, sDotNL
    call    PutStr
show:
    mov     ecx, r12d
    mov     edx, r13d
    call    Render
    lea     r8, wins
    cmp     byte ptr [r8+r12], 0
    je      humannotwon
    lea     rcx, sYouWin
    jmp     finish
humannotwon:
    cmp     byte ptr [r8+r13], 0
    je      compnotwon
    lea     rcx, sCompWin
    jmp     finish
compnotwon:
    mov     eax, r12d
    or      eax, r13d
    cmp     eax, 511
    jne     nextturn
    lea     rcx, sDraw
finish:
    call    PutStr
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
nextturn:
    xor     r14d, 1
    jmp     turn
PlayGame endp

; ---------------------------------------------------------------- benchmark
; Same workload as --bench in the other versions: the computer answers each of the nine human
; openings, once cold and then 199 more times. Reported in ns/move.
RunOpenings proc                            ; nine ComputerMove calls
    push    rbx
    xor     ebx, ebx
open1:
    mov     eax, 1
    mov     ecx, ebx
    shl     eax, cl
    mov     ecx, eax
    xor     edx, edx
    call    ComputerMove
    inc     ebx
    cmp     ebx, 9
    jb      open1
    pop     rbx
    ret
RunOpenings endp

Report proc                                 ; rcx = label, rax = ticks, r8 = move count
    push    rbx
    push    rsi
    sub     rsp, 24
    mov     rsi, r8
    mov     rbx, rax
    call    PutStr
    mov     rax, rbx                        ; ns per move = ticks * 1e9 / frequency / moves
    mov     rcx, 1000000000
    mul     rcx
    div     qpcFreq
    xor     edx, edx
    div     rsi
    mov     rcx, rax
    call    PutUInt
    lea     rcx, sNs
    call    PutStr
    add     rsp, 24
    pop     rsi
    pop     rbx
    ret
Report endp

Bench proc
    push    rbx
    sub     rsp, 32
    lea     rcx, qpcFreq
    call    QueryPerformanceFrequency

    lea     rcx, tStart
    call    QueryPerformanceCounter
    call    RunOpenings
    lea     rcx, tEnd
    call    QueryPerformanceCounter
    mov     rax, tEnd
    sub     rax, tStart
    mov     tCold, rax

    lea     rcx, tStart
    call    QueryPerformanceCounter
    mov     ebx, 199
later:
    call    RunOpenings
    dec     ebx
    jnz     later
    lea     rcx, tEnd
    call    QueryPerformanceCounter

    mov     rax, tCold
    lea     rcx, sFirst
    mov     r8d, 9
    call    Report
    mov     rax, tEnd
    sub     rax, tStart
    lea     rcx, sLater
    mov     r8d, 1791                       ; 9 * 199
    call    Report
    add     rsp, 32
    pop     rbx
    ret
Bench endp

; ---------------------------------------------------------------- startup
Init proc
    sub     rsp, 40
    mov     ecx, -11                        ; STD_OUTPUT_HANDLE
    call    GetStdHandle
    mov     hOut, rax
    mov     ecx, -10                        ; STD_INPUT_HANDLE
    call    GetStdHandle
    mov     hIn, rax

    lea     r9, wins                        ; build the win table
    lea     r10, lines
    xor     ecx, ecx
maskloop:
    cmp     ecx, 512
    jae     seeded
    xor     edx, edx
lineloop:
    cmp     edx, 8
    jae     nextmask
    mov     eax, [r10+rdx*4]
    mov     r8d, ecx
    and     r8d, eax
    cmp     r8d, eax
    jne     nextline
    mov     byte ptr [r9+rcx], 1
nextline:
    inc     edx
    jmp     lineloop
nextmask:
    inc     ecx
    jmp     maskloop
seeded:
    rdtsc                                   ; seed the generator from the time stamp counter
    shl     rdx, 32
    or      rax, rdx
    mov     rdx, 9E3779B97F4A7C15h
    imul    rax, rdx
    or      rax, 1
    mov     rng, rax
    add     rsp, 40
    ret
Init endp

HasBench proc                               ; eax = 1 when "--bench" is on the command line
    sub     rsp, 40
    call    GetCommandLineA
    mov     rcx, rax
scan:
    cmp     byte ptr [rcx], 0
    je      absent
    lea     rdx, sBench
    xor     r8d, r8d
cmpchar:
    movzx   eax, byte ptr [rdx+r8]
    test    al, al
    jz      present
    cmp     al, [rcx+r8]
    jne     nextpos
    inc     r8
    jmp     cmpchar
nextpos:
    inc     rcx
    jmp     scan
present:
    mov     eax, 1
    jmp     quitp
absent:
    xor     eax, eax
quitp:
    add     rsp, 40
    ret
HasBench endp

main proc
    sub     rsp, 40
    call    Init
    call    HasBench
    test    eax, eax
    jz      game
    call    Bench
    jmp     quit
game:
    lea     rcx, sTitle
    call    PutStr
again:
    call    PlayGame
    lea     rcx, sAgain
    call    PutStr
    call    ReadLine
    test    eax, eax
    jle     quit
    movzx   eax, linebuf
    or      al, 20h
    cmp     al, 'y'
    je      again
quit:
    call    Flush
    xor     ecx, ecx
    call    ExitProcess
main endp

end
