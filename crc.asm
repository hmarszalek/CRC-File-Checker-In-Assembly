section .data
    fd dq 0                            ; File descriptor

section .bss
    file resb 256                      ; 256 bytes for the file path
    file_len resq 1                    ; Qword to store the length of file path
    poly resb 64                       ; The string of CRC polynomial
    poly_len resq 1                    ; Qword to store the length of CRC
    crc resq 1                         ; Poly converted to integer
    control_sum resb 65                ; The string of control sum and newline character
    buffer resb 4                      ; Buffer to read bytes
    data resb 2048                     ; Block of data read
    data_len resq 1                    ; Current length of remembered data

section .text
global _start

; ------------------- Macros -------------------
SYS_READ equ 0
SYS_WRITE equ 1
SYS_OPEN equ 2
SYS_CLOSE equ 3
SYS_LSEEK equ 8
SEEK_CUR equ 1
O_RDONLY equ 0
SYS_EXIT equ 60

%macro read_file 2
    push rcx
    push rdi 
    push rsi
    push rdx

    lea rsi, %1
    mov rdx, %2
    mov rdi, [rel fd]
    mov rax, SYS_READ
    syscall

    ; Check for error when reading the file
    cmp rax, 0
    jl .error

    pop rdx
    pop rsi
    pop rdi
    pop rcx
%endmacro

%macro close_file 0
    mov rdi, [rel fd]
    mov rax, SYS_CLOSE
    syscall
%endmacro

%macro exit 1
    mov rdi, %1
    mov rax, SYS_EXIT
    syscall
%endmacro
; ----------------------------------------------

_start:
; Check the validity of parameters
; If they are correct, set up the program

    ; Retrieve and validate parameter count (should be 3)
    pop rsi                            ; Pop parameter count 
    cmp rsi, 3                         ; Check if it's correct (program name, file and CRC)
    jne .wrong_parameters              ; If it's not, exit with error

    pop rax                            ; Discard the program name

    ; Read file name
    pop rsi                            ; Get file from the stack
    lea rdi, [rel file]                ; Set destination address for the string
    call .get_len_of_string            ; Set rcx to the length of string
    mov qword [rel file_len], rcx      ; Store the length in second parameter
    rep movsb                          ; Copy rcx bytes from rsi to rdi

    ; Read polynomial
    pop rsi                            ; Get CRC polynomial from the stack
    lea rdi, [rel poly]                ; Set destination address for the string
    call .get_len_of_string            ; Set rcx to the length of string
    mov qword [rel poly_len], rcx      ; Store the length in second parameter
    rep movsb                          ; Copy rcx bytes from rsi to rdi

    ; If poly is empty or too long, return error
    cmp qword [rel poly_len], 0
    je .wrong_parameters
    cmp qword [rel poly_len], 64
    jg .wrong_parameters

    ; Open the file 
    mov rax, SYS_OPEN
    lea rdi, [rel file]
    mov rsi, O_RDONLY
    syscall

    cmp rax, 0                         ; If rax is set to 0, error occurred while opening the file
    jl .wrong_parameters               ; Most likely have wrong parameters
    mov qword [rel fd], rax            ; Save file descriptor

; Interpret poly as binary representation 
; Save in CRC decimal representation of it
    xor rax, rax                       ; Accumulate the result in rax
    lea rsi, [rel poly]                ; Move address of polynomial string to rsi
    mov rcx, [rel poly_len]            ; Iterate through each bit of poly
.pti_loop:
    movzx rdx, byte [rsi]              ; Get byte from polynomial
    inc rsi                            ; Go to next byte

    ; Check if crc is valid - only {0,1}
    cmp rdx, '0' 
    jl .wrong_parameters
    cmp rdx, '1'
    jg .wrong_parameters

    ; Put the bit in the result
    sub rdx, '0'
    shl rax, 1
    add rax, rdx

    dec rcx                            ; One less bit to go
    jnz .pti_loop                      ; If it's not 0 yet we have to iterate again
    mov [rel crc], rax                 ; Store the result in memory

; Calculating control sum
; rax - used to load data bytes
; rdi - index we are on in data buffer
; rdx - start of the block
; r8 - holds our control sum 
; r9 - polynomial mask

    ; Initialize values
    xor r8, r8                         ; r8 will hold our control sum
    xor rdx, rdx                       ; rdx is starting point of current block
    mov rdi, qword [rel data_len]      ; Set rdi to data_len, so the buffer_call starts

    ; Prepare the crc polynomial mask
    mov rcx, qword [rel poly_len]      ; Temporarily hold length of crc in rcx
    mov r9, 1                          ; Move one into r9 register
    shl r9, cl                         ; Shift it so its on the same place as the MSB of crc
    cmp r9, 1                          ; If shift didnt occure, we have a 64-bit polynomial
    cmove r9, r8                       ; Move 0 into regiter (as if it was shifted 64 bits)
    dec r9                             ; Get the highest integer without concerned bit said

    ; Read initial block length and put it in rcx
    call .read_block_len

.loop_calculate:
    cmp rdi, qword [rel data_len]      ; check if we need to refill the buffer
    je .fill_buffer_call
.continue_call:
    ; Process each byte in the current buffer
    lea r10, [rel data]                ; use r10 to temporarily hold data adress
    add r10, rdi                       ; increase it by rdi byte to get to the curret index

    mov al, byte [r10]                 ; load the next byte from the data buffer
    shl rax, 56

    inc rdi                            ; move to the next byte in the data buffer
    mov r10, 8                         ; iterate through 8 bits of the byte
.bit_loop:
    shld r8, rax, 1
    jc .crc_xor

    cmp r8, r9                         ; if r8>r9 then our Important Bit must be set
    jbe .no_xor

.crc_xor:
    sub r8, r9
    dec r8
    xor r8, qword [rel crc]
.no_xor:
    shl rax, 1                         ; shift al left by 1, so the next bit is ready
    dec r10                            ; decrease the iterator
    jnz .bit_loop
    jmp .loop_calculate                ; Otherwise get start loop for next byte

; Check if its the end of file
; If it is, exit the loop
; If its not collect more data and continue calculating
.fill_buffer_call:
    cmp qword [rel fd], -1             ; If the file is closed it means we read it entierly
    je .add_padding_bits               ; Complete last step and finish the program
    call .fill_buffer                  ; Otherwise fill the data buffer
    mov rdi, 0                         ; Set byte index back to 0
    jmp .continue_call                 ; Continue the calculation
    
; Add [poly_len] bits '0' to the end of data
.add_padding_bits:
    mov rcx, qword [rel poly_len]      ; Move length of crc-1 into rcx
.padding_loop:
    shl r8, 1                          ; Shift control sum left
    jc .padding_xor                    ; If we havent caught the bit earlier we have 64-bit poly
    cmp r8, r9                         ; Otherwise compare control sum with mask
    jbe .padding_no_xor                ; If its lower, we havent reached the '1' yet
.padding_xor:
    sub r8, r9                         ; Remove the '1' from the front
    dec r8                             ; Remove the '1' from the front
    xor r8, qword [rel crc]            ; Xor the control sum
.padding_no_xor:
    dec rcx                            ; One padding bit less
    jnz .padding_loop                  ; If not all padding bits processed, continue

    call .integer_to_string

    ; print the calculated control sum
    mov rax, SYS_WRITE
    mov rdi, 1
    lea rsi, [rel control_sum]
    mov rdx, [rel poly_len]
    inc rdx
    syscall

    ; exit the program with no error
    exit 0 

; Helper functions

; rax - used to find loops and check for error
; rcx - tells us how many more bytes in the block
; rdx - holds starting point of last block
; rsi - buffer adress (to copy bytes)
; rdi - data adress (we iterate through it)
.fill_buffer:
    lea rdi, [rel data]                ; rdi holds the data address
    mov qword [rel data_len], 0        ; set data_len to 0        
.fill_buffer_loop:
    jrcxz .get_shift
    cmp qword [rel data_len], 2048     ; check if next byte will fit in the [data]
    je .buffer_filled                  ; one less byte left in the current block
    call .read_data                    ; read data into the buffer
    jmp .fill_buffer_loop              ; if rcx isnt 0, continue filling the buffer

.get_shift:
; rdx - holds starting point of last block
; r10 - used to change position
    read_file [rel buffer], 4          ; Read shift (4 bytes) into the buffer
    mov esi, dword [rel buffer]        ; Move it from buffer to register
    movsxd rsi, esi                    ; Sign-extend it to qword
    mov r10, rdx                       ; Move starting point of last block to r10
    
    ; Change position in the file so it points to start of the new block
    push rdi 
    mov rdi, [rel fd]
    mov rdx, SEEK_CUR
    mov rax, SYS_LSEEK
    syscall
    ; Check for error while changing position
    cmp rax, 0
    jl .error
    pop rdi

    cmp r10,rax                        ; Check if its the starting position of the last block
    je .all_data_read                  ; If it is we reached the end of data
    mov rdx, rax                       ; If its not set new starting position

    call .read_block_len               ; Read the length of the next data block
    jmp .fill_buffer_loop              ; Continue filing the buffer until full
    
.all_data_read:
    close_file                         ; Safely close the file
    mov qword [rel fd], -1             ; Set file descriptor to -1 (indicates the file is closed)
.buffer_filled:
    ret

.read_block_len:
    read_file [rel buffer], 2          ; Read data length (2 bytes) into the buffer
    cmp rax, 0                         ; Check rax
    je .error                          ; if we read no bytes end of file -> error
    xor rcx, rcx                       ; clear rcx after syscall ruined it 
    mov cx, word [rel buffer]          ; get the length from the buffer
    ret

.read_data:
    ; rcx has the length of the block
    ; [data_len] holds how many bytes we already keep in the buffer
    ; We can read only min(rcx, 2048-[data_len])
    ; Number of bytes we want to read is held in r10
    mov r10, 2048                      ; Assume r10 is max buffer length
    sub r10, qword [rel data_len]      ; Substract from that number of bytes we are already using
    cmp rcx, r10                       ; Compare that to number of bytes left in the block
    cmovl r10, rcx                     ; If rcx isnt greater we can fill the buffer, otherwise we read only rcx byte
.read_data_loop:
    read_file [rdi], r10               ; Try reading next r10 bytes of file to data (rdi)
    cmp rax, 0                         ; If we are at the end of file it must have invalid structure
    je .error                          ; Exit the program

    ; We managed to read rax bytes
    add qword [rel data_len], rax      ; Value of data_len is rax bytes longer
    add rdi, rax                       ; We moved index of the next free byte
    sub rcx, rax                       ; There is rax less bytes left in the current block
    sub r10, rax                       ; We need to read rax bytes less
    jnz .read_data_loop                ; If we haven't read all of r10 bytes, try again
    ret

; Function finds length of string with adress in rsi and puts it in regiter rcx
.get_len_of_string:
    xor rcx, rcx                       ; Initialize rcx to 0
.get_len_loop:
    cmp byte [rsi+rcx], 0              ; Check if the currently read byte is null-terminate
    jz .got_len                        ; If it is, we went thorugh all the bits of the string
    inc rcx                            ; Otherwise increase rcx (there is one byte more)
    jmp .get_len_loop                  ; reapet until finding the end
.got_len:
    ret

; Function changes binary representetion of control sum into binary string
; Control sum is passed in r8 register and result is in control_sum
.integer_to_string:
    lea rdi, [rel control_sum]         ; Hold adress of control_sum in rdi
    ; Shift contorl sum so the MSB is first
    mov rax, qword [rel poly_len]
    mov rcx, 64
    sub rcx, rax
    shl r8, cl
.its_loop:
    shl r8, 1                          ; Shift left to get the next bit into the carry flag
    mov byte [rdi], '0'                ; Assume the bit is 0
    adc byte [rdi], 0                  ; Add carry (will add 1 if bit was 1)
    inc rdi                            ; Move to the next buffer position
    dec rax                            ; One lest bit to go
    jnz .its_loop                      ; Loop until all bits are processed
    mov byte [rdi], 10                 ; Add end of line character
    ret

; exit with error
.error:
    close_file
.wrong_parameters:
    exit 1