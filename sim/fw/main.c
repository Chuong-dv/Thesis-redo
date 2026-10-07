#define MAILBOX (*(volatile unsigned int *)0x1FF0)

int main(void)
{
    MAILBOX = 0x600DF00D;     /* testbench se bat cu nay tren bus */
    for (;;) { }
}
