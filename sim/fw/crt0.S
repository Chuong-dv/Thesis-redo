    .section .init
    .globl _start
_start:
    la   sp, _stack_top      # ngan xep nam trong RAM
    call main
1:  j    1b                  # main tra ve thi dung o day
