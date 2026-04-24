# Phase 3 - Domain layer, policy và nghiệp vụ

Phase này là lõi nghiệp vụ. Nó quyết định dữ liệu nào được xem là kết quả hợp lệ, mode nào được ưu tiên, và câu nói nào sẽ được phát ra.

Nếu muốn hiểu đúng app này, bạn cần hiểu phase này đầu tiên trong số các phase “thực sự quyết định hành vi”. Những phần còn lại chủ yếu là nền tảng hoặc giao diện.

## Phần chính

### `lib/features/safe_vision/domain/usecases/initialize_vision_usecase.dart`

Use case này chỉ có một nhiệm vụ: gọi `visionRepository.initializeCamera()`.

Nó tách ý nghĩa nghiệp vụ khỏi chi tiết camera, để Bloc không cần biết camera được khởi tạo như thế nào.

Nói dễ hiểu: bloc chỉ cần gọi “hãy chuẩn bị hệ thống nhìn”, không cần biết mở camera thế nào, load tracker ra sao.

### `lib/features/safe_vision/domain/usecases/detect_objects_usecase.dart`

Use case này bọc `visionRepository.detect(image)`.

Bloc chỉ nhìn thấy đây là “phát hiện object từ một khung hình”, còn cách ghép tracker + TFLite là việc của repository.

Điểm lợi của cách này là sau này nếu bạn đổi model, đổi pipeline, hoặc thêm cache thì bloc không phải sửa.

### `lib/features/safe_vision/domain/usecases/speak_message_usecase.dart`

Use case này bọc `speechRepository`.

- `configure()` cấu hình tiếng Việt.
- `call(message, interrupt)` phát âm.
- `stop()` dừng phát âm.
- `isSpeaking` cho biết TTS đang nói hay không.

Use case này giống như một điều khiển tối giản cho loa: chuẩn bị, nói, dừng, và kiểm tra trạng thái.

### `lib/features/safe_vision/domain/services/safe_vision_policy.dart`

Đây là nơi quan trọng nhất của domain.

Lớp này làm 3 việc chính:

1. Lọc detections theo mode.
2. Tạo chuỗi `statusText` cho UI.
3. Tạo payload giọng nói cho TTS.

Đây là nơi biến dữ liệu thô thành quyết định có ý nghĩa với người dùng.

#### `filterDetectionsForMode()`

- Ở `tutorial`, không giữ detection nào.
- Ở `indoor`, giữ toàn bộ detection.
- Ở `outdoor`, chỉ giữ những object có tính cảnh báo, object nằm trong vùng nguy hiểm, hoặc object luôn phải warn như lửa.

Hiểu theo cách gần gũi:

- indoor là chế độ tìm vật trong nhà, nên thấy gì cũng có thể hữu ích
- outdoor là chế độ an toàn đường đi, nên chỉ những thứ thật sự liên quan đến nguy hiểm mới cần ưu tiên
- tutorial là chế độ học cách dùng, nên không làm người dùng bị nhiễu bởi detection

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

Nó còn sinh `messageKey` và `warningKeys` để Bloc chống lặp câu nói quá dày.

Hai giá trị này rất quan trọng:

- `warningKeys` giúp biết warning nào đã xuất hiện để quyết định có cần nhấn mạnh lại không
- `messageKey` giúp biết nội dung câu nói có thực sự khác hay chỉ là object bị dao động số lượng qua từng frame

Ví dụ: nếu xe vẫn còn đó nhưng bounding box dao động nhẹ, app không nên nói lại y hệt mỗi khung hình.

### `lib/features/safe_vision/domain/entities/detection.dart`

`Detection` là model dữ liệu cho một object đã được nhận diện.

Hãy coi nó như “thẻ thông tin” của một vật thể: label là nó là gì, score là chắc đến mức nào, và 4 tọa độ là nó đang nằm ở đâu trên ảnh.

Các property chính:

- `label` là nhãn gốc.
- `score` là độ tin cậy.
- `left`, `top`, `right`, `bottom` là tọa độ normalized.
- `width`, `height`, `areaRatio`, `centerX` là helper để tính logic cảnh báo.

`labelVi` là helper chuyển một số label phổ biến sang tiếng Việt.

Điều này giúp phần hiển thị và phần nói chuyện với người dùng thân thiện hơn mà không phải dịch toàn bộ hệ thống ở nhiều nơi.

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

## Cách domain giao tiếp với Bloc

Bloc không tự soạn luật.

Nó chỉ:

1. Nhận event.
2. Gọi use case.
3. Nhận `Detection` hoặc message đã được policy xử lý.
4. Update state.

Nói ngắn gọn: domain trả lời “nên làm gì”, còn Bloc quyết định “khi nào làm”.

Đây là lý do project này dễ mở rộng hơn các app gom toàn bộ logic vào UI: khi luật thay đổi, bạn chủ yếu sửa trong policy hoặc use case, không phải lục lại toàn bộ widget.

