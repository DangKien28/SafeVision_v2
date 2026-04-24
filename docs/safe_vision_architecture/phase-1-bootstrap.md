# Phase 1 - Khởi động và dependency injection

Phase này trả lời câu hỏi: app bắt đầu từ đâu, ai tạo các object chính, và widget nào được đưa lên màn hình đầu tiên.

Nếu ví dự án như một ngôi nhà thì phase này là phần nền móng và hệ thống điện nước. Nó chưa làm “nghiệp vụ chính”, nhưng nếu làm sai ở đây thì các phase sau sẽ khó chạy ổn định.

## Phần chính

### `lib/main.dart`

Đây là điểm vào của Flutter.

- `WidgetsFlutterBinding.ensureInitialized()` bảo đảm framework và các plugin native sẵn sàng trước khi app chạy.
- `runApp(const SafeVisionApp())` khởi tạo widget gốc của toàn bộ app.

Vai trò của file này rất nhỏ nhưng rất quan trọng: nó không chứa nghiệp vụ, chỉ mở cổng cho app chạy.

Nói dễ hiểu: đây là nút bật nguồn của toàn bộ ứng dụng.

### `lib/app.dart`

`SafeVisionApp` là nơi dựng dependency chính và cấu hình giao diện toàn app.

File này giống như nơi lắp ráp các bộ phận trước khi đưa app ra sử dụng. Nó quyết định object nào sống lâu, object nào phụ thuộc vào object nào, và dữ liệu đi vào bloc từ đâu.

Luồng tạo object trong `initState()`:

1. Tạo `CameraDataSource` để làm việc với camera vật lý.
2. Tạo `MlKitTrackerDataSource` để track object và detect person ROI.
3. Tạo `TfliteDetectorDataSource` để chạy model TFLite `assets/best_int8.tflite`.
4. Tạo `TtsDataSource` để phát âm.
5. Bọc các data source vào `VisionRepositoryImpl` và `SpeechRepositoryImpl`.
6. Tạo 3 use case: `InitializeVisionUseCase`, `DetectObjectsUseCase`, `SpeakMessageUseCase`.
7. Tạo `SafeVisionBloc` và giữ nó trong biến `_bloc`.

Điểm quan trọng ở đây là thứ tự tạo object không ngẫu nhiên:

- camera phải có trước vì các model sẽ đọc frame từ camera
- tracker và detector phải được bọc vào repository để bloc không biết chi tiết kỹ thuật
- TTS phải có trước khi bloc bắt đầu phát thông báo

Nếu bạn hiểu được luồng này, bạn sẽ hiểu vì sao sau này bloc có thể gọi một hàm duy nhất mà hệ thống vẫn làm rất nhiều việc phía dưới.

`build()` của `SafeVisionApp` làm 2 việc:

- Cấu hình `ThemeData` với màu và typography riêng của app.
- Cung cấp `_bloc` xuống cây widget bằng `BlocProvider.value`, rồi hiển thị `SafeVisionPage`.

## Class con và vai trò

### `CameraDataSource`

Lớp này giữ `CameraController`, danh sách camera, lens hiện tại, hướng cảm biến và hướng xoay thiết bị.

Nó là tầng gần phần cứng nhất trong feature camera.

Đầu vào của nó là yêu cầu khởi tạo hoặc đổi camera. Đầu ra của nó là một `CameraController` đã sẵn sàng để hiển thị preview và stream frame.

### `MlKitTrackerDataSource`

Lớp này là cầu nối với ML Kit.

- Một detector phục vụ tracking box.
- Một detector khác phục vụ tìm person để lấy ROI.(Vùng quan tâm)

Nói đơn giản, lớp này dùng để “bám” vào các vật thể đang di chuyển và phát hiện vùng ưu tiên quanh người để lần sau detector TFLite chạy nhanh hơn.

### `TfliteDetectorDataSource`

Lớp này nạp model TFLite và chạy suy luận trong isolate riêng để tránh block UI.

Đây là phần nặng nhất về tính toán. Nếu chạy trực tiếp trên main isolate thì UI sẽ dễ giật, nên project đẩy công việc này sang isolate riêng.

### `TtsDataSource`

Lớp này bọc `FlutterTts`, cấu hình tiếng Việt và điều khiển phát âm.

Bạn có thể hiểu nó như loa thông minh của app: nhận câu chữ, đọc ra tiếng Việt, và cho biết đang nói hay đã dừng.

### `VisionRepositoryImpl` và `SpeechRepositoryImpl`

Hai class này gom logic từ data source thành một API sạch hơn cho domain.

Lý do tách repository là để domain và bloc không phải biết mỗi thứ plugin nào đang dùng, format dữ liệu bên trong ra sao, hay camera, ML Kit, TFLite được ghép như thế nào.

### `SafeVisionBloc`

Bloc được tạo ở phase này nhưng chưa chạy nghiệp vụ ngay. Nó chỉ chờ `SafeVisionPage` bắn event `SafeVisionStarted`.

Bloc là người điều phối trung tâm. Nó không trực tiếp xử lý camera hay model, nhưng nó quyết định khi nào gọi cái gì, và state nào nên được cập nhật cho UI.

## Tương tác thực tế

- `main.dart` khởi động app.
- `SafeVisionApp` dựng dependency.
- `BlocProvider` cung cấp `SafeVisionBloc`.
- `SafeVisionPage` sẽ dùng bloc đó để bắt đầu phase tiếp theo.

Nếu đọc theo hướng runtime thì đây là thứ tự thực sự:

1. App mở.
2. Dependency được dựng.
3. Bloc được gắn vào cây widget.
4. Page xuất hiện.
5. Page bắn event khởi động.
6. Mọi xử lý chính bắt đầu chuyển sang các phase sau.

