# Phase 4 - Data layer và xử lý AI/camera/TTS

Phase này đi vào phần kỹ thuật nặng hơn: camera, TFLite, isolate và TTS.

Nếu phase 3 trả lời “nên làm gì” thì phase 4 trả lời “làm bằng cách nào”.

## Phần chính

### `lib/features/safe_vision/data/repositories/vision_repository_impl.dart`

Đây là lớp ghép camera và TFLite thành API detection cho domain.

Nó dựa trên 2 data source:

- `CameraDataSource` để lấy frame và đổi camera.
- `TfliteDetectorDataSource` để chạy model object detection.

Nhìn từ ngoài vào, repository này giống như bộ máy hợp nhất 2 nguồn dữ liệu khác nhau để tạo ra kết quả detection ổn định cho bloc.

Trong kiến trúc hiện tại, tracking object và điều tiết giọng nói không nằm ở tầng data nữa mà đã được đẩy lên domain (`IoUObjectTracker` và `AudioManager`).

#### `initializeCamera()`

Luồng này làm 2 việc:

1. Khởi tạo camera.
2. Load TFLite model.

Tức là khi bloc gọi một hàm duy nhất, repository đã âm thầm chuẩn bị cả camera lẫn model suy luận.

#### `detect()`

Đây là phần chính của pipeline:

1. Tính rotation phù hợp theo orientation và lens direction.
2. Gọi TFLite worker để detect object từ frame camera.
3. Trả về danh sách detection thô cho domain xử lý tiếp.

Điểm quan trọng của chiến lược này là lớp data không tự quyết định object nào đáng nói hay đáng cảnh báo. Nó chỉ trả detection ra khỏi model, còn tracking, policy và TTS cooldown đều do domain xử lý.

### `lib/features/safe_vision/data/datasources/camera_data_source.dart`

Lớp này quản lý camera vật lý.

Các nhiệm vụ chính:

- `initializeCamera()` mở camera theo lens direction.
- `switchCamera()` đổi giữa camera trước và sau.
- `startImageStream()` bắt đầu stream frame.
- `dispose()` dọn controller.

Đây là lớp gần hệ điều hành nhất trong phần app này. Nó không hiểu object detection, chỉ hiểu việc mở, đổi, bắt đầu stream và dọn camera.

### `lib/features/safe_vision/data/datasources/tflite_detector_data_source.dart`

Đây là lớp chạy TFLite inference.

#### `load()`

- Load labels từ asset.
- Load model bytes từ asset.
- Tạo isolate worker.
- Chờ worker gửi signal `ready`.

Lý do dùng isolate là vì inference TFLite có thể nặng. Tách ra isolate giúp UI vẫn mượt trong lúc model xử lý.

Trong `app.dart`, repository hiện trỏ tới `assets/best_float16.tflite` và `assets/labels.txt`.

#### `detect()` và `detectInRoi()`

- `detect()` chạy suy luận trên toàn khung hình.
- `detectInRoi()` chạy trong một ROI rồi map tọa độ quay về ảnh gốc.

Hai hàm này cho bạn hai chế độ: quét toàn cảnh và quét vùng hẹp. Repository sẽ chọn cái phù hợp tùy từng frame.

#### `_requestDetection()`

Đóng gói YUV planes của `CameraImage` và gửi sang isolate để xử lý.

Điểm đáng chú ý: class này dùng `Completer` để match request/response theo `requestId`.

Nói đơn giản, mỗi frame gửi đi như một “phiếu yêu cầu”, rồi response quay về đúng phiếu đó để không bị nhầm lẫn khi nhiều frame chạy liên tiếp.

### `lib/features/safe_vision/data/datasources/tts_data_source.dart`

Lớp này bọc `FlutterTts`.

- `configureVietnamese()` đặt ngôn ngữ, tốc độ, pitch và volume.
- `speak()` phát âm và có thể ngắt câu đang nói.
- `stop()` dừng nói.
- `dispose()` dọn trạng thái.

Đây là phần phát giọng nói cuối cùng, nên nó phải thật ổn định về trạng thái `isSpeaking` để bloc và `AudioManager` quyết định có nên ngắt hay chờ.

### `lib/features/safe_vision/data/repositories/speech_repository_impl.dart`

Repository này chỉ ủy quyền sang `TtsDataSource`, nhưng nó giúp domain chỉ phụ thuộc vào interface `SpeechRepository`.

Đây là một lớp mỏng, nhưng vẫn cần thiết cho kiến trúc sạch: domain chỉ biết “speech repository”, không biết package TTS cụ thể.

## Quan hệ giữa các class data

`VisionRepositoryImpl` là lớp điều phối ở tầng data. Nó không tự đọc camera hay tự detect bằng tay; nó gọi đúng data source cho đúng việc và trả kết quả detection cho bloc.

`SpeechRepositoryImpl` là lớp mỏng, nhưng giúp tách nghiệp vụ TTS ra khỏi framework `flutter_tts`.

Nếu bạn muốn hình dung pipeline theo trình tự dữ liệu, hãy nhớ chuỗi này:

camera frame -> TFLite -> raw detections -> domain tracker/policy -> UI/TTS

Đây chính là “đường ống” xử lý của toàn bộ feature.
