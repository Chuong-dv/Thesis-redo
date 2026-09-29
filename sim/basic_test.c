#define RAM_BASE    0x00000000
#define UART_BASE   0x40000000
#define GPIO_BASE   0x40010000
#define ASCON_BASE  0x40030000

// Macro gán địa chỉ thanh ghi
#define UART_TX     (*(volatile unsigned int *)(UART_BASE + 0x00))
#define GPIO_OUT    (*(volatile unsigned int *)(GPIO_BASE + 0x04))
#define ASCON_CTRL  (*(volatile unsigned int *)(ASCON_BASE + 0x00))

void delay(int loops) {
    while(loops--) { asm volatile("nop"); }
}

int main() {
    // 1. TEST RAM (Nếu hàm main chạy được đến đây, tức là RAM wrapper đã đúng)
    int test_var = 0; 

    // 2. TEST GPIO
    GPIO_OUT = 0x0000000F; // Bật 4 LED
    delay(100);
    GPIO_OUT = 0x00000000; // Tắt LED

    // 3. TEST UART (Gửi 2 chữ "OK")
    UART_TX = 'O';
    UART_TX = 'K';

    // 4. TEST ASCON (Khởi động Soft Reset thử)
    ASCON_CTRL = 0x10; // Ghi bit thứ 4 = 1 để kích hoạt ctrl_soft_rst

    while(1) {
        // Vòng lặp vô tận, giữ CPU không chạy ra khỏi vùng RAM
    }
    return 0;
}