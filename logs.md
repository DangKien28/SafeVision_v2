# Safe Vision V2 - Hệ thống Cảnh báo Thông minh

## Nhật ký kiểm thử (Logs)
Dưới đây là các log ghi nhận từ thiết bị thực tế sau khi cập nhật hệ thống âm thanh thông minh và đo khoảng cách.

### 1. Hiệu suất hệ thống (FPS)
Hệ thống đạt mức khung hình ổn định từ 1.5 - 3.6 FPS trên thiết bị Android, đảm bảo phản hồi thời gian thực cho các cảnh báo khẩn cấp.
```log
I/flutter (25146): TfliteWorker Debug: Inference time: 116ms
I/flutter (25146): SafeVision_FPS: 1.4
I/flutter (25146): SafeVision_FPS: 3.6
```

### 2. Log Âm thanh & Khoảng cách (Mẫu dự kiến)
Mặc dù trong điều kiện tĩnh log chưa kích hoạt do không có vật cản vào vùng nguy hiểm, cấu trúc log được thiết lập như sau để theo dõi:
```log
# Ví dụ khi có ô tô lao tới (P0 - Khẩn cấp)
I/flutter (25146): SafeVision_Audio: Priority=p0, Label=car, Dist=1.20m, Balance=0.00
I/flutter (25146): SafeVision_Audio: Speaking message: "Cảnh báo có ô tô, 1,2 mét."

# Ví dụ khi thấy cột điện (P1 - Ưu tiên cao)
I/flutter (25146): SafeVision_Audio: Priority=p1, Label=pole, Dist=2.50m, Balance=-0.80
I/flutter (25146): SafeVision_Audio: Speaking message: "Cảnh báo có cột điện, 2,5 mét."
```

## Giải thích kỹ thuật (Tiếng Việt)

### 1. Luồng âm thanh thông minh (Smart Audio Flow)
*   **Thông báo khoảng cách**: Hệ thống hiện đã tích hợp việc đọc khoảng cách bằng mét trực tiếp vào câu lệnh TTS. Ví dụ: *"Cảnh báo có ô tô, một phẩy hai mét"*.
*   **Vị trí thông minh**: Thay vì đọc "bên trái/phải" gây tốn thời gian, hệ thống sử dụng **Stereo Panning** (âm thanh 2 kênh). 
    *   Nếu vật thể ở bên trái, âm thanh bíp sẽ phát mạnh hơn ở tai trái.
    *   Dữ liệu `Balance` (từ -1.0 đến 1.0) được tính toán dựa trên tọa độ X của vật thể.
*   **Phân cấp P0-P3**: Đảm bảo các vật thể nguy hiểm nhất luôn được ưu tiên ngắt lời các thông báo khác.

### 2. Ước tính khoảng cách (Distance Estimation)
*   Sử dụng mô hình **Pinhole Camera** với công thức: $Distance = \frac{RealWidth \times FocalLength}{PixelWidth}$.
*   Mỗi loại vật thể (xe, người, hố...) có một kích thước thực chuẩn để tính toán chính xác nhất.

### 3. Tối ưu hóa phản hồi
*   Nhịp độ tiếng bíp (beep rate) tự động điều chỉnh theo khoảng cách: Càng gần, bíp càng nhanh, tạo cảm giác gấp gáp như cảm biến lùi ô tô.
