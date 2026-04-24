# 👁️ SafeVision: Hệ thống hỗ trợ di chuyển an toàn cho người khiếm thị

[cite_start]**SafeVision** là một ứng dụng di động đột phá kết hợp Trí tuệ nhân tạo (AI) và Thị giác máy tính (Computer Vision) để hỗ trợ người khiếm thị di chuyển độc lập và an toàn hơn trong môi trường giao thông phức tạp tại Việt Nam[cite: 2, 10]. [cite_start]Dự án được phát triển bởi đội ngũ sinh viên Đại học Duy Tân trong khuôn khổ Hội nghị Sinh viên Nghiên cứu khoa học năm học 2025-2026[cite: 1, 5].

## 📌 Tổng quan dự án
[cite_start]Khác với các giải pháp truyền thống như gậy trắng hay các ứng dụng quốc tế đắt đỏ, SafeVision tập trung vào khả năng **xử lý tại biên (Edge AI)** — thực hiện nhận diện vật thể ngay trên điện thoại mà không cần kết nối Internet ổn định, giúp giảm độ trễ và bảo vệ quyền riêng tư[cite: 11, 50].

### Các tính năng chính:
* [cite_start]**Nhận diện vật thể thời gian thực:** Sử dụng mô hình YOLOv8 được tối ưu hóa để nhận diện các loại xe máy, ô tô, người đi bộ, hố ga, và các chướng ngại vật đặc trưng tại Việt Nam[cite: 12, 64].
* [cite_start]**Cảnh báo giọng nói tiếng Việt:** Tích hợp Google Text-to-Speech để đưa ra các chỉ dẫn và cảnh báo bằng giọng nói tự nhiên[cite: 12, 56].
* [cite_start]**Thiết kế Accessibility-First:** Giao diện tối giản với độ tương phản cực cao và điều khiển bằng cử chỉ vuốt/chạm toàn màn hình, phù hợp tối đa cho người có thị lực kém[cite: 82, 84].
* [cite_start]**Hoạt động Offline:** Mô hình được nén định dạng `.tflite` (chỉ từ 3-4MB) giúp chạy mượt mà trên các thiết bị Android tầm trung[cite: 11, 74].

## 🛠️ Công nghệ sử dụng
* [cite_start]**Core AI:** YOLOv8 (Ultralytics)[cite: 11, 45].
* [cite_start]**Framework Mobile:** Flutter (Dart)[cite: 54].
* [cite_start]**Optimization:** TensorFlow Lite (Quantization & Pruning)[cite: 53].
* [cite_start]**Ngôn ngữ bổ trợ:** Python (Training model), C++/C# (Hệ thống bổ trợ)[cite: 52].
* [cite_start]**Quản lý dự án:** Quy trình Agile/Scrum[cite: 65].

## 🏗️ Kiến trúc hệ thống
[cite_start]Hệ thống hoạt động theo luồng khép kín từ Camera -> Xử lý AI (Edge) -> Phân tích ngữ cảnh -> Cảnh báo âm thanh (TTS)[cite: 57].
1.  [cite_start]**Block 1:** Smartphone Camera thu thập luồng hình ảnh[cite: 57].
2.  [cite_start]**Block 2:** SafeVision System (YOLOv8 + TFLite) xử lý trực tiếp trên thiết bị[cite: 57].
3.  [cite_start]**Block 3 & 4:** Hệ thống phân tích vật thể và chuyển đổi thành văn bản/giọng nói[cite: 57].
4.  [cite_start]**Block 5:** Người dùng nhận phản hồi âm thanh để định hướng di chuyển[cite: 57].

## 🚀 Cài đặt
Để chạy dự án này cục bộ, bạn cần cài đặt Flutter SDK và môi trường Android Studio.

```bash
# Clone repository
git clone https://github.com/dangkien28/safevision_v2.git

# Di chuyển vào thư mục dự án
cd safevision_v2

# Cài đặt các dependencies
flutter pub get

# Chạy ứng dụng trên thiết bị Android (đã kết nối)
flutter run
```

*Lưu ý: Đảm bảo file mô hình `best_float16.tflite` đã nằm trong thư mục `assets/` trước khi biên dịch.*

## 📈 Kết quả thực nghiệm
* [cite_start]**Độ chính xác (mAP50):** Đạt trên 88% với bộ dữ liệu đường phố Việt Nam[cite: 73].
* [cite_start]**Hiệu suất:** Tốc độ xử lý từ 15 - 22 FPS trên thiết bị tầm trung[cite: 78].
* [cite_start]**Phản hồi:** Độ trễ gần như bằng 0, đáp ứng tốt việc di chuyển thực tế[cite: 79].

## 👥 Đội ngũ thực hiện
Dự án được quản lý bởi **SVR**:
* [cite_start]**Scrum Master & AI Engineer:** Đặng Trung Kiên (Chairman)[cite: 66].
* [cite_start]**Mobile Developer:** Trần Tiến Đạt[cite: 66].
* [cite_start]**AI Engineer:** Nguyễn Trung Kiên[cite: 66].
* [cite_start]**Data & Tester:** Nguyễn Thị Thu Anh, Huỳnh Minh Tiến[cite: 66].
* **Giảng viên hướng dẫn:** ThS. [cite_start]Lê Văn Tính[cite: 6].

## 🛡️ Giấy phép
Dự án này được phát triển cho mục đích nghiên cứu khoa học và cộng đồng người khiếm thị Việt Nam. Mọi sao chép hoặc sử dụng cho mục đích thương mại cần có sự đồng ý từ đội ngũ phát triển.

---
[cite_start]*SafeVision - "Con mắt số" đồng hành cùng người khiếm thị.* [cite: 100]