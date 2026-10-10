# Kết quả kiểm chứng ISA cho `rvx_core_wb`

> Quy ước trạng thái: **ĐÃ XÁC NHẬN** = có bằng chứng từ mô phỏng. **CHỜ XÁC NHẬN** = mới là dự đoán từ việc đọc source/test, chưa có bằng chứng.

## 1. Môi trường (để chạy lại được)

| Hạng mục | Giá trị |
|---|---|
| Core | `rvx_core_wb`, `BOOT_ADDRESS = 0x8000_0000`, MIMPID = 6, MARCHID = 0x18 (theo CSR trong source).  |
| Bộ test | `riscv-software-src/riscv-tests`, commit `<git rev-parse HEAD>`, `XLEN=32`,  |
| Toolchain | `riscv64-unknown-elf-gcc <phiên bản>`, `-march=rv32i -mabi=ilp32` |
| Mô phỏng | Vivado xsim v2023.2 |
| Testbench | `tb/tb_core.sv`: core nối trực tiếp với `rvx_ram_wb` (64 KB), nạp hex bằng `$readmemh`, bắt cú ghi `tohost`, watchdog |
| Danh sách test | `isa_hex/list.txt` (42 test `rv32ui-p-*`), `mi_hex/list.txt` (16 test `rv32mi-p-*`); mỗi dòng gồm tên test và địa chỉ `tohost` |
| Lệnh chạy | `./regress_isa.sh isa_hex` và `./regress_isa.sh mi_hex` |

Cách một test báo kết quả: ghi vào `tohost`. Giá trị `1` là đạt, `(n << 1) | 1` là fail ở test con thứ `n`, và `1337 | TESTNUM` là "ngoại lệ lạ" của môi trường test (không phải một phép kiểm sai).

## 2. Tổng hợp

| Bộ | Đạt | Fail | Trong đó miễn trừ | Còn mở |
|---|---|---|---|---|
| `rv32ui-p` (42 test) | 41 | 1 | 1 | 0 |
| `rv32mi-p` (16 test) | 13 | 3 | 1 | 2 |

Tính theo test áp dụng được: `rv32ui` 41/41; `rv32mi` 13/15 (loại `pmpaddr` do core không có PMP, sau khi xác nhận).

## 3. Chi tiết các test fail

### 3.1 `rv32ui-p-ma_data` — MIỄN TRỪ 

- **Test kiểm gì:** load/store lệch địa chỉ phải được phần cứng thực hiện và cho kết quả đúng.
- **Thiết kế của core:** `misaligned_load`/`misaligned_store` gây ngoại lệ (mcause 4 / 6). Đặc tả RISC-V cho phép cả hai cách (thực hiện bằng phần cứng hoặc báo ngoại lệ).
- **Bằng chứng:**
  ```
  [1670000] TRAP: mcause=4 mtval=80002001 mepc=8000019c
  TEST FAILED: tohost = 00000539
  ```
  `mepc = 0x8000019c` là lệnh `lh t2,1(s0)` (test con số 1), `mtval = 0x80002001` là `s0 + 1` với `s0 = 0x80002000`; `0x539 = 1 | 1337`.
- **Test thay thế đang đạt:** `rv32mi-p-lh-misaligned`, `lw-misaligned`, `sh-misaligned`, `sw-misaligned`, `ma_addr` (kiểm đúng `mcause`, `mepc`, `mtval` và không ghi ngược `rd`).
- **Ngày:** `07/10/2026`

### 3.2 `rv32mi-p-pmpaddr` — MIỄN TRỪ 

- **Test kiểm gì:** ghi `-1` vào `pmpaddr0`, đọc lại để dò độ mịn PMP. Comment đầu file ghi "assumes PMP is available".
- **Giả thuyết:** core không có PMP (tính năng tùy chọn), nên đọc `pmpaddr0` ra 0 và test fail ở test con số 1.
- **Cần xác nhận:** `tohost = 00000003` và không có dòng `TRAP:`.
-   [ ] Đã chạy, kết quả:
    ```
    [1930000] TRAP: mcause=11 mtval=00000000 mepc=80000298
    TEST FAILED: tohost = 00000003 (fail o buoc 1)`
    ```
- **Miễn trừ**. Ghi tài liệu "core không hỗ trợ PMP".

### 3.3 `rv32mi-p-instret_overflow` — LỖI CORE MỨC THẤP (CHỜ XÁC NHẬN)

- **Test kiểm gì:** test 2: `csrwi minstret,0` rồi `csrr a0,minstret` phải đọc ra `0` (ghi vào `minstret` thì lệnh ghi không được đếm thêm).
- **Nguyên nhân RTL (từ đọc source):** ở nhánh ghi `minstret` trong `STATE_OPERATING`, source viết `csr_minstret <= {csr_minstret[63:32], csr_write_data} + 1;`. Có `+ 1` nên đọc lại ra `1`. Nhánh ghi `minstreth` có cùng dạng.
- **Cần xác nhận:** `tohost = 00000005` (test 2 fail) và không có dòng `TRAP:`.
  - [ ] Đã chạy, kết quả: 
    ```
    [1970000] TRAP: mcause=11 mtval=00000000 mepc=80000210
    TEST FAILED: tohost = 00000005 (fail o buoc 2)
    ```
- **Xử lý dự kiến:** bỏ `+ 1` ở hai nhánh ghi (`minstret`, `minstreth`), giữ nguyên `+ 1` ở nhánh đếm thường.

### 3.4 `rv32mi-p-ma_fetch` — LỖI CORE NGHI NGỜ (BẰNG CHỨNG MỘT PHẦN)

- **Test kiểm gì:** test 2: `jalr t1,2(t0)` (đích không căn 4 byte) phải gây ngoại lệ **mà không ghi `t1`**. Handler kiểm: `t1 == 0`, `mcause == 0`, `mepc` là địa chỉ `jalr`, `mtval == 0` hoặc `t0 + 2`.
- **Đã xác nhận (log ngày 2026-10-08):**
  ```
  [1730000] TRAP: mcause=0 mtval=800001b2 mepc=800001ac
  [2170000] TRAP: mcause=11 mtval=00000000 mepc=800002ec
  TEST FAILED: tohost = 00000005
  ```
  `mcause`, `mepc` (`0x800001ac` là `jalr`, `+4 = t0 = 0x800001b0`) và `mtval` (`t0 + 2`) đều khớp. Lần trap thứ hai (`mcause = 11`) là `ecall` trong nhánh `fail`, không mang thông tin nguyên nhân.
- **Giả thuyết (suy luận loại trừ, chưa có bằng chứng trực tiếp):** `t1` bị ghi khi lệnh trap.
- **Nguyên nhân RTL nghi ngờ:** `integer_file_write_enable = integer_file_write_request & !flush & !load_pending;` thiếu điều kiện `take_trap`. Ở chu kỳ phát hiện đích lệch, trạng thái còn là `OPERATING` nên `flush = 0`; `load_pending` chỉ chặn load (đó là lý do các test `*-misaligned` đạt).
- **Cần xác nhận:** vết thực thi tại `pc=800001ac` phải có đồng thời `take_trap=1` và `rf_we=1`, `rd=x6`, `wdata=800001b0`.
  - [ ] Đã chạy `+TRACE`, kết quả: `<điền>`
- **Xử lý dự kiến:** thêm `& !take_trap` vào biểu thức trên.

## 4. Nhật ký thay đổi RTL và chạy lại

Giữ log của lần fail trước khi sửa, đặt tên `run_<test>_before_fix.log`.

| Ngày | Thay đổi RTL (file, dòng) | `rv32ui` | `rv32mi` | Hoàn tác thử có fail lại không | Ghi chú |
|---|---|---|---|---|---|
| `9/10/2026` | (chưa sửa; trạng thái cơ sở) | 41/42 | 13/16 | - | |
| `10/10/2026` | Sua loi lenh instret_overflow & ma_fetch             | 41/42 | 15/16 | - | |

## 5. Phạm vi chưa phủ và việc tiếp theo

- **Ngắt:** bộ `riscv-tests` không kiểm ngắt. Từ việc đọc source, nếu việc ghi `rd` không bị chặn khi `take_trap` đến từ ngắt, lệnh bị ngắt sẽ ghi `rd` rồi chạy lại sau `mret` (ví dụ `addi a0,a0,1` làm `a0` tăng hai lần). **Đây mới là giả thuyết.** Cần một test ngắt định hướng.
- **Checker toàn cục:** thêm cảnh báo `VIOLATION` khi `take_trap && integer_file_write_enable && rd != 0` và chạy trên mọi test.
- **Độ trễ bộ nhớ thay đổi, `halt`:** RAM của testbench luôn trả lời cùng một nhịp; chưa kiểm khi phản hồi chậm hoặc khi bật `halt`.
- **So sánh từng lệnh với mô hình tham chiếu** (spike hoặc golden model trong UVM): chưa làm.

## 6. Cách đọc một test fail (tóm tắt quy trình)

1. Lấy `tohost` và các dòng `TRAP:` từ log.
2. Nếu `tohost` lẻ thông thường: `n = tohost >> 1`, tìm `li gp,n` trong file `.dump`. Nếu là `1337 | TESTNUM`: lấy `mepc` và tìm địa chỉ đó trong dump.
3. Đọc đoạn code trong dump, rồi mở file `.S` (và `test_macros.h`) để hiểu ý định kiểm tra.
4. Xác định check nào fail, tìm tín hiệu RTL chịu trách nhiệm, bắt tín hiệu đó bằng vết ở đúng chu kỳ.
5. Sửa RTL, chạy lại cả hai bộ, hoàn tác thử để xác nhận test bắt được lỗi.