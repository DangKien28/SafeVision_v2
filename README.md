# 👁️ SafeVision: Artificial Intelligence Application for Safe Navigation

> **Ứng dụng trí tuệ nhân tạo trong hỗ trợ di chuyển an toàn cho người khiếm thị.**
> Dự án tham gia *Hội nghị Sinh viên Nghiên cứu khoa học Khoa Đào Tạo Quốc Tế (Lần IV) - 2025-2026*.

![SafeVision Banner](https://img.shields.io/badge/AI-SafeVision-blue?style=for-the-badge)
![Tech Stack](https://img.shields.io/badge/YOLOv8-TFLite-orange?style=for-the-badge)
![Platform](https://img.shields.io/badge/Flutter-Mobile-lightgrey?style=for-the-badge)

## 📖 Giới thiệu (Introduction)

**SafeVision** là một giải pháp Computer Vision mang tính nhân đạo và chi phí thấp, được thiết kế chuyên biệt để hỗ trợ người khiếm thị di chuyển an toàn. Hệ thống sử dụng mô hình học sâu (Deep Learning) chạy trực tiếp trên thiết bị di động (Edge AI) để phát hiện vật cản theo thời gian thực.

Đặc biệt, hệ thống được bản địa hóa 100% cho môi trường giao thông đặc thù tại Việt Nam (ngõ hẻm, xe máy lấn làn, biển báo thấp, hố ga, v.v.), khắc phục hoàn toàn những điểm mù của gậy dò đường truyền thống.

## 🎯 Bài toán khoa học & Khác biệt

Các công cụ truyền thống như gậy dò đường có bán kính quét vật lý hẹp (<1.5m) và vô hiệu với chướng ngại vật treo cao. Các giải pháp công nghệ khác như kính thông minh thì chi phí quá cao, hoặc các App Cloud thì có độ trễ lớn và phụ thuộc mạng.

**Giải pháp của SafeVision:**
- **Thiết bị:** Tận dụng Smartphone sẵn có (Miễn phí).
- **Mô hình:** Real-time Object Detection với Edge Inference (Xử lý Offline).
- **Dữ liệu:** Tối ưu hóa tuyệt đối cho hạ tầng giao thông Việt Nam nhằm giảm thiểu độ trễ và tỷ lệ dương tính giả (False Positives).

## ⚙️ Kiến trúc hệ thống (System Architecture)

SafeVision hoạt động theo luồng **Edge AI C&C**:

1. **Camera Stream (Flutter UI):** Thu thập hình ảnh theo thời gian thực.
2. **Tiền xử lý khung hình:** Tối ưu hóa ảnh đầu vào.
3. **TFLite Inference Engine (YOLOv8):** Cốt lõi của hệ thống, sử dụng mô hình YOLOv8 đã được lượng tử hóa (Quantization & Pruning) từ `~12MB (.pt)` xuống `~3MB (.tflite)` để tương thích với phần cứng Mobile.
4. **Bộ Lọc Logic (Risk Zone >30%):** Thuật toán tính toán diện tích Bounding Box. *Nguyên tắc Accessibility First:* Chỉ kích hoạt cảnh báo khi vật cản chiếm >30% khung hình nhằm tránh gây quá tải nhận thức cho người dùng.
5. **Cảnh báo âm thanh:** Sử dụng Google Text-to-Speech phát âm thanh tiếng Việt.

**Ưu điểm của Edge AI:**
- ⚡ **Khử độ trễ mạng (Zero Latency):** Xử lý 100% on-device.
- 🔒 **Bảo mật dữ liệu:** Hình ảnh không bao giờ bị truyền lên cloud.
- 📶 **Độc lập:** Hoạt động hoàn hảo ở vùng sóng yếu hoặc không có Internet.

## 📊 Hiệu suất & Đánh giá (Performance)

Mô hình đã được huấn luyện qua hơn 50 epochs với dữ liệu bản địa hóa đa điều kiện (ngày, đêm, mưa, ngược sáng) và đạt được hiệu suất hội tụ xuất sắc (không Overfitting):

* **mAP@0.5:** 87.5%
* **Max F1-Score:** 0.84
* **Precision:** 1.00 (Độ tin cậy cao)
* **Tốc độ nhận diện (Inference Speed):** 15 - 22 FPS trên thiết bị di động.
* **Độ trễ phản hồi:** Tiệm cận 0.
* **Tầm nhìn số:** 3 - 5 Mét.

**Điểm nổi bật trong nhận diện:** Độ chính xác cực cao với Tiền VNĐ (92%-100%), Xe cộ (88%), và Cảnh báo hỏa hoạn (80%).

## 🚀 Lộ trình phát triển tương lai (Roadmap)

- [ ] **Q1:** Tích hợp bộ lọc hình ảnh (Denoising) cho thời tiết khắc nghiệt.
- [ ] **Q2:** Tích hợp LBS & GPS Routing (Dẫn đường bằng giọng nói từ A đến B).
- [ ] **Q3:** Nhận diện khuôn mặt giúp người dùng tái hòa nhập xã hội.
- [ ] **Q4:** Giao thức khẩn cấp (SOS) - Tự động gửi cảnh báo định vị cho người giám hộ.

## 👥 Đội ngũ nghiên cứu

Dự án được phát triển dưới sự hướng dẫn của **ThS. Lê Văn Tịnh**, với đội ngũ sinh viên bao gồm:

* **Đặng Trung Kiên:** Scrum Master / AI Engineer
* **Nguyễn Trung Kiên:** AI Engineer
* **Trần Tiến Đạt:** Mobile Developer
* **Nguyễn Thị Thu Anh:** Data / Tester
* **Huỳnh Minh Tiến:** Data / Tester

---
*Dự án áp dụng phương pháp quản trị Agile/Scrum với vòng đời 5 Sprints.*