# Phase 4 - Data layer và xử lý AI/camera/TTS

Phase này đi vào phần kỹ thuật nặng hơn: camera, ML Kit, TFLite, isolate và TTS.

Nếu phase 3 trả lời “nên làm gì” thì phase 4 trả lời “làm bằng cách nào”.

## Phần chính

### `lib/features/safe_vision/data/repositories/vision_repository_impl.dart`

Đây là lớp ghép nhiều nguồn dữ liệu thành kết quả detection ổn định hơn.

Nó dựa trên 3 data source:

- `CameraDataSource` để lấy frame và đổi camera.
- `MlKitTrackerDataSource` để track object và tìm person ROI.
- `TfliteDetectorDataSource` để chạy model object detection.

Nhìn từ ngoài vào, repository này giống như bộ máy hợp nhất 3 nguồn dữ liệu khác nhau để tạo ra một kết quả cuối cùng nhất quán hơn.

#### `initializeCamera()`

Luồng này làm 3 việc:

1. Khởi tạo camera.
2. Load ML Kit tracker.
3. Load TFLite model.

Tức là khi bloc gọi một hàm duy nhất, repository đã âm thầm chuẩn bị cả camera lẫn các model phụ trợ cần thiết.

#### `detect()` và `_detectHybrid()`

Đây là phần chính của pipeline:

1. Tăng frame counter.
2. Chạy tracker ML Kit để có box đang hoạt động.
3. Thỉnh thoảng refresh ROI của người bằng detector riêng.
4. Thỉnh thoảng chạy YOLO/TFLite lại thay vì chạy mỗi frame.
5. Ghép box tracked với label từ YOLO.
6. Trả về danh sách detection đã fusion.

Điểm quan trọng của chiến lược này là không làm TFLite chạy ở mọi frame. TFLite được dùng xen kẽ, còn ML Kit tracker hỗ trợ giữ tính liên tục giữa các frame.

Nhờ vậy app không phải chạy full detector cho mọi frame, nhưng vẫn giữ kết quả tương đối ổn định.

#### `_runYoloWithRoi()`

Nếu đã có ROI của người, repository có thể chỉ chạy detector trong ROI đó để giảm chi phí tính toán.

Điều này giống như việc bạn không tìm tất cả mọi thứ trong một căn phòng lớn mỗi lần, mà chỉ soi kỹ vùng có người hoặc vùng có khả năng quan trọng hơn.

#### `_refreshTrackLabelCache()` và `_fuseTrackedWithLabels()`

Hai hàm này giúp giữ label của một object ổn định qua nhiều frame.

- `_refreshTrackLabelCache()` cập nhật cache label theo tracking id.
- `_fuseTrackedWithLabels()` ghép box tracked với label tốt nhất từ YOLO hoặc cache.

Phần này giải quyết một vấn đề thực tế: tracker có thể bám tốt vị trí, còn detector có thể biết label tốt. Ghép hai thứ lại sẽ cho kết quả vừa ổn định vừa có nghĩa.

#### `_nonMaxSuppression()`

Loại bớt các detection chồng lấn mạnh nhau để tránh box trùng.

Nếu không có bước này, một object có thể bị vẽ nhiều box chồng lên nhau, làm giao diện rối và khiến TTS nói lặp.

### `lib/features/safe_vision/data/datasources/camera_data_source.dart`

Lớp này quản lý camera vật lý.

Các nhiệm vụ chính:

- `initializeCamera()` mở camera theo lens direction.
- `switchCamera()` đổi giữa camera trước và sau.
- `startImageStream()` bắt đầu stream frame.
- `dispose()` dọn controller.

Đây là lớp gần hệ điều hành nhất trong phần app này. Nó không hiểu object detection, chỉ hiểu việc mở, đổi, bắt đầu stream và dọn camera.

Lớp này là nơi duy nhất chạm trực tiếp `CameraController` trong feature.

### `lib/features/safe_vision/data/datasources/mlkit_tracker_data_source.dart`

Lớp này bọc ML Kit object detector.

#### `load()`

Khởi tạo 2 detector:

- `_trackerDetector` dùng để track object.
- `_personDetector` dùng để phát hiện person nhằm tạo ROI.

Từ góc nhìn kiến trúc, đây là phần “con mắt phụ” hỗ trợ pipeline chính, chứ không phải phần tạo kết quả cuối cùng.

#### `track()`

Chuyển `CameraImage` sang `InputImage`, chạy detector, rồi đổi kết quả sang `MlKitTrackedBox`.

Mục tiêu của hàm này là lấy được box đang chuyển động và giữ cho box đó có tracking id nếu ML Kit cung cấp.

#### `detectPersonRois()`

Tìm các object có label giống person/human, rồi nới box ra một chút để làm vùng ưu tiên cho detector TFLite.

Đây là tối ưu hoá rất thực dụng: nếu có người trong khung hình, app sẽ ưu tiên soi kỹ khu vực quanh người trước vì đó thường là nơi đáng chú ý hơn.

### `lib/features/safe_vision/data/datasources/tflite_detector_data_source.dart`

Đây là lớp chạy TFLite inference.

#### `load()`

- Load labels từ asset.
- Load model bytes từ asset.
- Tạo isolate worker.
- Chờ worker gửi signal `ready`.

Lý do dùng isolate là vì inference TFLite có thể nặng. Tách ra isolate giúp UI vẫn mượt trong lúc model xử lý.

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

Đây là phần phát giọng nói cuối cùng, nên nó phải thật ổn định về trạng thái `isSpeaking` để bloc quyết định có nên ngắt hay chờ.

### `lib/features/safe_vision/data/datasources/mlkit_input_image_converter.dart`

Lớp tiện ích này chuyển `CameraImage` sang `InputImage` cho ML Kit.

Nó xử lý hai việc khó:

- Chuyển định dạng YUV420 sang NV21 trên Android.
- Tính rotation đúng theo sensor orientation và device orientation.

Phần này quan trọng vì nếu rotation sai thì ML Kit sẽ đọc khung hình lệch hướng, dẫn đến kết quả detection hoặc tracking không đúng vị trí thực tế.

### `lib/features/safe_vision/data/repositories/speech_repository_impl.dart`

Repository này chỉ ủy quyền sang `TtsDataSource`, nhưng nó giúp domain chỉ phụ thuộc vào interface `SpeechRepository`.

Đây là một lớp mỏng, nhưng vẫn cần thiết cho kiến trúc sạch: domain chỉ biết “speech repository”, không biết package TTS cụ thể.

## Quan hệ giữa các class data

`VisionRepositoryImpl` là lớp điều phối ở tầng data. Nó không tự đọc camera hay tự detect bằng tay; nó gọi đúng data source cho đúng việc và ghép kết quả lại.

`SpeechRepositoryImpl` là lớp mỏng, nhưng giúp tách nghiệp vụ TTS ra khỏi framework `flutter_tts`.

Nếu bạn muốn hình dung pipeline theo trình tự dữ liệu, hãy nhớ chuỗi này:

camera frame -> tracker -> ROI -> TFLite -> fusion -> policy -> UI/TTS

Đây chính là “đường ống” xử lý của toàn bộ feature.

