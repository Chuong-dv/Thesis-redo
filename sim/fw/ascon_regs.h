#ifndef ASCON_REGS_H
#define ASCON_REGS_H

#define ASCON_BASE      0x80050000u
#define REG(addr)       (*(volatile unsigned int *)(addr))

#define ASCON_CTRL      REG(ASCON_BASE + 0x00)   /* bit0 start, bit1 decrypt, bit2 is_ad, bit3 variant, bit4 soft reset */
#define ASCON_STATUS    REG(ASCON_BASE + 0x04)   /* bit0 data_ready, bit1 irq_done, bit2 out_valid */
#define ASCON_KEY(i)    REG(ASCON_BASE + 0x10 + 4u * (i))   /* i = 0..3, word 0 = bit 31:0 */
#define ASCON_NONCE(i)  REG(ASCON_BASE + 0x20 + 4u * (i))
#define ASCON_TAG(i)    REG(ASCON_BASE + 0x30 + 4u * (i))   /* doc, word 0 = bit 31:0 */

/* Trigger: ghi vao la day block vao core */
#define ASCON_TRIG_LAST_NODATA   REG(ASCON_BASE + 0x54)     /* block cuoi, khong co byte nao */
#define ASCON_TRIG_NORM_NODATA   REG(ASCON_BASE + 0x58)     /* block thuong, khong co byte moi */

#define ST_READY        0x1u
#define ST_IRQ          0x2u

/* Mailbox: testbench bat cac cu ghi vao dia chi nay tren bus cua master */
#define MAILBOX         REG(0x1FF0u)
#define PASS_MARKER     0x600DF00Du
#define FAIL_MARKER(c)  (0xBAD00000u | (c))

static inline void __attribute__((noreturn)) finish(unsigned int code)
{
    MAILBOX = code;
    for (;;) { }
}

/* Cho cho den khi (status & mask) == mask; qua gioi han thi bao FAIL voi ma 'code' */
static inline void wait_status(unsigned int mask, unsigned int code)
{
    int n = 0;
    while ((ASCON_STATUS & mask) != mask) {
        if (++n > 5000) finish(FAIL_MARKER(code));
    }
}

#endif
