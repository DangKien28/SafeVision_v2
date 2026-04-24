# Phase 5 - Luồng chạy end-to-end

Phase này ghép toàn bộ app thành một vòng đời hoàn chỉnh, từ lúc mở app đến lúc phát cảnh báo.

Đây là phần quan trọng nhất nếu bạn muốn hiểu toàn hệ thống chạy thực tế như thế nào.

## 1. App khởi động

1. `main()` chạy trong [lib/main.dart](../../lib/main.dart).
2. Flutter mount `SafeVisionApp`.
3. `SafeVisionApp` tạo `CameraDataSource`, `TfliteDetectorDataSource`, `TtsDataSource`, repository, use case và `SafeVisionBloc` trong [lib/app.dart](../../lib/app.dart).
4. `BlocProvider` đưa bloc xuống `SafeVisionPage`.

Ở thời điểm này app mới chỉ lắp xong bộ máy. Chưa có camera stream, chưa có detection, chưa có TTS nói gì cả.

## 2. Màn hình mở ra

1. `SafeVisionPage.initState()` bắn `SafeVisionStarted`.
2. `SafeVisionBloc._onStarted()` chạy.
3. Bloc gọi `_loadTtsMetadata()` để nạp metadata label tiếng Việt từ `assets/labels_vi.json`.
4. Bloc gọi `SpeakMessageUseCase.configure()` để đặt TTS tiếng Việt.
5. Bloc gọi `InitializeVisionUseCase()` để mở camera và load model.
6. Bloc gọi `VisionRepository.startImageStream(_enqueueFrame)` để bắt đầu stream frame.
7. State được cập nhật để UI hiện preview và status “Safe Vision đang hoạt động”.
8. Bloc phát câu chào ban đầu để báo hệ thống đã sẵn sàng.

Đây là mốc mà app bắt đầu thực sự “thức dậy”. Trước đó chỉ là giai đoạn chuẩn bị.

## 3. Camera stream bắt đầu

Mỗi frame camera đi qua chuỗi sau:

1. `CameraDataSource` đẩy `CameraImage` lên callback `_enqueueFrame()`.
2. Bloc throttle frame theo `_frameThrottleMs` và bỏ qua frame nếu đang xử lý frame trước đó.
3. Nếu frame hợp lệ, Bloc bắn event `CameraFrameReceived(image)`.

Điểm cần nhớ là bloc chỉ cho một frame được xử lý tại một thời điểm. Điều này giữ cho detection và TTS không bị chồng chéo khi camera trả frame quá nhanh.

## 4. Detect object

1. `SafeVisionBloc._onFrameReceived()` gọi `DetectObjectsUseCase(image)`.
2. Use case gọi `VisionRepository.detect(image)`.
3. `VisionRepositoryImpl` đẩy frame sang TFLite worker và trả về raw detections.
4. Bloc chạy `IoUObjectTracker.process()` để ổn định tracking id và box.
5. Kết quả raw detections quay lại Bloc.

Đây là nơi ảnh thô được biến thành dữ liệu có ý nghĩa: object nào, ở đâu, độ tin cậy bao nhiêu, và object nào đang là cùng một thực thể qua nhiều frame.

## 5. Áp dụng policy theo mode

1. Bloc gọi `SafeVisionPolicy.filterDetectionsForMode(...)`.
2. Bloc gọi `SafeVisionPolicy.buildStatusText(...)`.
3. Bloc update state với `rawDetections`, `detections`, `statusText` và FPS hiện tại.
4. `SafeVisionPage` rebuild các widget liên quan: overlay, status bar, action bar.

Từ đây trở đi, cùng một frame nhưng mỗi mode có thể cho ra kết quả hiển thị khác nhau. Đó là lý do mode rất quan trọng.

## 6. Phát cảnh báo giọng nói

1. Bloc đưa detections đã lọc sang `AudioManager.processDetections(...)`.
2. `SafeVisionPolicy.buildSpeechPayload(...)` tạo message, warning keys và message key.
3. `AudioManager` dùng tracking id, cooldown và độ ưu tiên để tránh spam câu nói.
4. Nếu đang nói mà có cảnh báo mới, `AudioManager` có thể dừng câu cũ rồi gọi `SpeakMessageUseCase` để nói câu mới.
5. `SpeakMessageUseCase` gọi `SpeechRepository` rồi xuống `TtsDataSource` để phát âm.

Phần chặn lặp giọng nói này rất quan trọng cho trải nghiệm người dùng. Nếu không có nó, app sẽ đọc lặp cùng một câu rất nhiều lần.

## 7. Đổi mode

Khi người dùng vuốt hoặc bấm nút mode:

1. UI bắn `SafeVisionModeSwiped` hoặc `SafeVisionModeChanged`.
2. Bloc cập nhật mode hiện tại.
3. Bloc reset tracker và `AudioManager` để tránh giữ nhịp cũ sang mode mới.
4. `SafeVisionPolicy` lọc lại detections theo mode mới.
5. Bloc phát câu mô tả phù hợp cho mode đó.

Ví dụ:

- đang ở outdoor, app tập trung cảnh báo nguy hiểm
- chuyển sang indoor, app chuyển sang mô tả vật dụng
- chuyển sang tutorial, app chỉ nhắc cách thao tác

## 8. Đổi camera

Khi người dùng bấm nút đổi camera:

1. UI bắn `CameraLensToggled`.
2. Bloc đặt `isInitializing = true` để chặn thao tác trong lúc đổi camera.
3. Bloc reset tracker và `AudioManager`.
4. `VisionRepository.switchCamera()` đóng camera cũ và mở camera mới.
5. Stream ảnh được bật lại.
6. State cập nhật `isFrontCamera` và `cameraController` mới.
7. TTS báo đã chuyển camera.

Ở bước này, app cần vừa đổi nguồn ảnh vừa giữ giao diện không bị đơ. Vì vậy trạng thái `isInitializing` được bật tạm thời.

## 9. Tổng kết vai trò từng lớp trong runtime

- `SafeVisionPage` tạo input của người dùng và hiển thị state.
- `SafeVisionBloc` điều phối mọi bước runtime.
- `InitializeVisionUseCase`, `DetectObjectsUseCase`, `SpeakMessageUseCase` là lớp mỏng giúp tách nghiệp vụ.
- `SafeVisionPolicy`, `IoUObjectTracker` và `AudioManager` quyết định luật kinh doanh và nhịp đọc.
- `VisionRepositoryImpl` và `SpeechRepositoryImpl` xử lý phần ghép plugin/native.
- `CameraDataSource`, `TfliteDetectorDataSource`, `TtsDataSource` là các adapter chạm vào plugin/native.

Nếu bạn chỉ nhớ một câu, hãy nhớ câu này:

UI chỉ gửi ý định, bloc điều phối, domain áp luật và nhịp đọc, data làm việc nặng.
