#include "ascon_regs.h"

int main(void)
{
    unsigned int s = ASCON_STATUS;
    MAILBOX = s;                              /* ghi nhat ky: mong doi 0 */
    if (s & 1u) finish(FAIL_MARKER(1));       /* data_ready phai bang 0 truoc khi start */

    ASCON_CTRL = 1u;                          /* start */

    int n = 0;
    do {
        s = ASCON_STATUS;
        if (++n > 2000) finish(FAIL_MARKER(2));   /* core khong bao ready */
    } while ((s & 1u) == 0);

    MAILBOX = s;                              /* ghi nhat ky: mong doi bit 0 = 1 */
    finish(PASS_MARKER);
}
