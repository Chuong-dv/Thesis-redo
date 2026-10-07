#include "ascon_regs.h"

/* Ascon-128, key = 000102..0F, nonce = 101112..1F, AD rong, message rong.
   Tag mong doi = 38CCA290 D1F2EF3D F9C85319 46499037 (doc theo word, word 0 la 31:0). */
static const unsigned int key_w[4]   = { 0x0C0D0E0Fu, 0x08090A0Bu, 0x04050607u, 0x00010203u };
static const unsigned int nonce_w[4] = { 0x1C1D1E1Fu, 0x18191A1Bu, 0x14151617u, 0x10111213u };
static const unsigned int tag_exp[4] = { 0x46499037u, 0xF9C85319u, 0xD1F2EF3Du, 0x38CCA290u };

int main(void)
{
    int i;

    for (i = 0; i < 4; i++) {
        ASCON_KEY(i)   = key_w[i];
        ASCON_NONCE(i) = nonce_w[i];
    }

    ASCON_CTRL = 1u;                       /* start: ASCON-128, ma hoa, AD rong */
    wait_status(ST_READY, 1);              /* cho init xong */

    ASCON_TRIG_LAST_NODATA = 0u;           /* block cuoi, rong */
    wait_status(ST_IRQ, 2);                /* cho tag */

    for (i = 0; i < 4; i++) {
        unsigned int t = ASCON_TAG(i);
        MAILBOX = t;                       /* nhat ky */
        if (t != tag_exp[i]) finish(FAIL_MARKER(0x10 + i));
    }
    finish(PASS_MARKER);
}
