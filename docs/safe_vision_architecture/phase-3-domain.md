# Phase 3 - Domain layer, policy và nghiệp vụ

Phase này là lõi nghiệp vụ. Nó quyết định dữ liệu nào được xem là hợp lệ, object nào đáng cảnh báo, và câu nói nào sẽ được phát ra.

Nếu muốn hiểu đúng app này, bạn cần nhìn phase này như nơi đặt luật vận hành của toàn bộ feature Safe Vision.

## Phần chính

### `lib/features/safe_vision/domain/usecases/initialize_vision_usecase.dart`

Use case này chỉ có một nhiệm vụ: gọi `visionRepository.initializeCamera()`.

Bloc không cần biết camera được mở thế nào hay model được nạp ra sao. Nó chỉ cần gọi một hành động có ý nghĩa: chuẩn bị hệ thống nhìn.

### `lib/features/safe_vision/domain/usecases/detect_objects_usecase.dart`

Use case này bọc `visionRepository.detect(image, confidenceThreshold)`.

Bloc chỉ nhìn thấy đây là “phát hiện object từ một khung hình”, còn chi tiết TFLite và rotation là việc của repository.

### `lib/features/safe_vision/domain/usecases/speak_message_usecase.dart`

Use case này bọc `speechRepository`.

- `configure()` cấu hình tiếng Việt.
- `call(message, interrupt)` phát âm.
- `stop()` dừng phát âm.
- `isSpeaking` cho biết TTS đang nói hay không.

Đây là wrapper mỏng quanh speech để bloc không phải biết plugin TTS cụ thể.

### `lib/features/safe_vision/domain/services/object_tracker.dart`

`IoUObjectTracker` giữ ổn định danh tính và vị trí object qua nhiều frame.

Nó ghép detection mới với track cũ nếu box chồng lấn đủ lớn, rồi gán `trackingId` cho detection đầu ra.

Vai trò chính của nó là:

- giữ bounding box mượt hơn qua các frame liên tiếp
- hạn chế việc cùng một vật thể bị coi là object mới mỗi frame
- tạo nền cho `AudioManager` áp cooldown theo từng track

### `lib/features/safe_vision/domain/services/audio_manager.dart`

`AudioManager` là lớp điều tiết nhịp đọc TTS ở runtime.

Nó không tự hiểu camera hay model, mà chỉ nhìn vào detections đã được policy lọc để quyết định:

- có nên nói ngay hay không
- có cần ngắt câu cũ để nói cảnh báo mới hay không
- có cần giữ im lặng vì cùng một message vừa đọc xong hay không
- có nên lưu lại trạng thái theo `trackingId` để tránh spam theo từng frame hay không

Nếu không có lớp này, app có thể đọc lặp cùng một cảnh báo liên tục chỉ vì camera trả frame rất nhanh.

### `lib/features/safe_vision/domain/services/safe_vision_policy.dart`

Đây là nơi quan trọng nhất của domain.

Lớp này làm 4 việc chính:

1. Lọc detections theo mode.
2. Quyết định object nào nằm trong vùng nguy hiểm.
3. Tạo chuỗi `statusText` cho UI.
4. Tạo payload giọng nói cho TTS.

`SafeVisionPolicy` dựa vào metadata nhãn để chia object thành 3 nhóm:

- `warning` cho cảnh báo nguy hiểm
- `instruction` cho vật thể cần chú ý khi di chuyển
- `recognition` cho object bình thường

Nhờ vậy cùng một detection, app có thể chọn cách nói khác nhau tùy ngữ cảnh.

#### `filterDetectionsForMode()`

- Ở `tutorial`, không giữ detection nào.
- Ở `indoor`, giữ toàn bộ detection.
- Ở `outdoor`, chỉ giữ những object có tính cảnh báo, object nằm trong vùng nguy hiểm, hoặc object luôn phải warn như lửa.

Ngoài mode, hàm này còn ưu tiên các object có vùng chiếm ảnh đủ lớn và sắp xếp theo độ nguy hiểm, diện tích và score để UI và TTS đều đọc kết quả ổn định hơn.

#### `buildStatusText()`

Tạo câu ngắn cho thanh trạng thái:

- `tutorial` nhắc vuốt trái/phải.
- `indoor` mô tả vật thể tìm thấy.
- `outdoor` ưu tiên cảnh báo nguy hiểm.

`statusText` là câu ngắn ở đầu màn hình, được thiết kế để người dùng hiểu nhanh tình huống hiện tại mà không phải nhìn quá nhiều chi tiết.

#### `buildSpeechPayload()`

Đây là phần quyết định app sẽ nói gì.

- `tutorial` thì không nói detection.
- `indoor` gom theo label và nói kiểu “Tìm thấy ...”.
- `outdoor` chỉ nói các object nằm trong vùng nguy hiểm hoặc object bắt buộc cảnh báo.

Nó còn sinh `messageKey` và `warningKeys` để AudioManager và Bloc chống lặp câu nói quá dày.

### `lib/features/safe_vision/domain/entities/detection.dart`

`Detection` là model dữ liệu cho một object đã được nhận diện.

Nó giống như “thẻ thông tin” của một vật thể: label là nó là gì, score là chắc đến mức nào, và 4 tọa độ là nó đang nằm ở đâu trên ảnh.

Các property chính:

- `label` là nhãn gốc.
- `score` là độ tin cậy.
- `left`, `top`, `right`, `bottom` là tọa độ normalized.
- `width`, `height`, `areaRatio`, `centerX`, `estimatedDistance` là helper để tính logic cảnh báo.
- `trackingId` giúp nối cùng một vật thể qua nhiều frame.

`labelVi` là helper chuyển một số label phổ biến sang tiếng Việt.

### `lib/features/safe_vision/domain/entities/safe_vision_mode.dart`

Enum này xác định 3 mode của app:

- `outdoor`
- `indoor`
- `tutorial`

Ý nghĩa thực tế của từng mode:

- `outdoor`: ưu tiên cảnh báo nguy hiểm trên đường đi
- `indoor`: ưu tiên nhận diện vật dụng trong nhà
- `tutorial`: chỉ hướng dẫn thao tác, không gây nhiễu bằng cảnh báo detection

### `lib/features/safe_vision/domain/repositories/vision_repository.dart`

Đây là contract của tầng vision.

Bloc và use case chỉ phụ thuộc vào interface này, không phụ thuộc vào implementation cụ thể.

### `lib/features/safe_vision/domain/repositories/speech_repository.dart`

Đây là contract của tầng speech/TTS.

Ngoài `configureVietnamese()`, `speak()` và `stop()`, repository còn có `dispose()` để dọn tài nguyên TTS khi app đóng hoặc khi cần reset tầng speech.

## Cách domain giao tiếp với Bloc

Bloc không tự soạn luật.

Nó chỉ:

1. Nhận event.
2. Gọi use case.
3. Nhận `Detection` đã được tracker ổn định hoặc message đã được policy xử lý.
4. Dùng `AudioManager` để quyết định khi nào nên phát âm.
5. Update state.

Nói ngắn gọn: domain trả lời “nên làm gì”, còn Bloc quyết định “khi nào làm”.

Đây là lý do project này dễ mở rộng hơn các app gom toàn bộ logic vào UI: khi luật thay đổi, bạn chủ yếu sửa trong policy, tracker hoặc audio manager, không phải lục lại toàn bộ widget.
