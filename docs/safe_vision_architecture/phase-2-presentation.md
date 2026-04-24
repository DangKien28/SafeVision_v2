# Phase 2 - Presentation layer và tương tác UI

Phase này trả lời câu hỏi: màn hình hiển thị gì, người dùng thao tác ra sao, và event nào được bắn vào Bloc.

Nếu phase 1 là dựng máy, thì phase 2 là bảng điều khiển. Người dùng chạm vào đây, còn việc thật sự sẽ được xử lý ở bloc và domain.

## Phần chính

### `lib/features/safe_vision/presentation/pages/safe_vision_page.dart`

Đây là màn hình chính của feature.

#### `initState()`

- Lấy `SafeVisionBloc` từ context.
- Bắn `SafeVisionStarted()` để bắt đầu khởi tạo camera, model, TTS và stream ảnh.

Đây là điểm rất quan trọng: page không tự đi khởi tạo camera. Nó chỉ nói với bloc rằng “hãy bắt đầu”. Cách làm này giúp UI sạch và dễ kiểm soát hơn.

#### `build()`

Màn hình được ghép bằng `Stack`:

- Lớp nền là preview camera.
- Lớp phủ trên là box detection.
- Góc trên trái là `TopStatusBar`.
- Góc trên phải là nút đổi camera.
- Dưới cùng là `BottomActionBar`.

Bạn có thể hình dung như sau:

- camera preview là nền chính
- detection box là lớp đánh dấu lên trên
- status bar là phần thông tin tóm tắt
- nút đổi camera là điều khiển nhanh
- thanh mode là nơi chọn ngữ cảnh sử dụng

#### Cử chỉ người dùng

- Vuốt ngang sẽ bắn `SafeVisionModeSwiped(toNext: ...)`.
- Bấm nút đổi camera sẽ bắn `CameraLensToggled()`.
- Bấm một mode ở thanh dưới sẽ bắn `SafeVisionModeChanged(mode)`.

Những event này không thay đổi UI ngay tại chỗ. Chúng chỉ gửi ý định của người dùng lên bloc. Bloc sẽ là nơi quyết định state mới và cách render mới.

### `BlocBuilder` trong page

Page không tự tính toán nghiệp vụ. Nó chỉ đọc state:

- `isInitializing` và `cameraController` để quyết định có hiện `LoadingPanel` hay không.
- `detections` để vẽ overlay bằng `DetectionPainter`.
- `statusText` và `mode` để cập nhật `TopStatusBar`.
- `isFrontCamera` để đổi nhãn nút camera trước/sau.

Điểm quan trọng: page có nhiều `BlocBuilder` nhỏ, mỗi cái chỉ rebuild khi một phần state thay đổi. Đây là cách giảm rebuild thừa.

Điều này giúp app nhẹ hơn vì:

- preview camera không cần rebuild mỗi khi status text đổi
- status bar không cần rebuild mỗi khi detection box đổi
- overlay không cần rebuild mỗi khi chỉ đổi camera front/back

Nói ngắn gọn: chia nhỏ `BlocBuilder` là cách tối ưu hiệu năng và giữ code dễ đọc.

## Class con và vai trò

### `SafeVisionPage`

Là container logic UI ở tầng presentation. Nó không xử lý AI, chỉ phát sinh event và render state.

Vai trò của nó là kết nối người dùng với bloc.

### `TopStatusBar`

Hiển thị tên mode hiện tại và `statusText` do Bloc tính ra.

Nếu status bar đổi, nghĩa là bloc vừa tính lại trạng thái nhận diện hoặc chế độ hoạt động.

### `BottomActionBar`

Hiển thị 3 mode: ngoài trời, trong nhà, hướng dẫn.

Nó nhận `onModeChanged` từ page, nhưng không tự biết rule nào của từng mode.

Điều này giúp widget tái sử dụng được ở nơi khác nếu sau này bạn muốn đặt thanh mode vào màn khác.

### `DetectionPainter`

Vẽ bounding box và nhãn tiếng Việt từ danh sách `Detection`.

Đây là lớp chỉ có nhiệm vụ “vẽ”, không được phép quyết định object nào đúng hay sai. Quyết định đó đã nằm ở policy và repository rồi.

### `LoadingPanel`

Hiển thị trạng thái đang khởi tạo camera / model / stream.

Người dùng nhìn thấy panel này trong thời gian camera và model chưa sẵn sàng.

## Cách các class tương tác

1. Người dùng mở page.
2. `initState()` bắn `SafeVisionStarted`.
3. Bloc xử lý xong sẽ cập nhật state.
4. `BlocBuilder` trên page nhận state mới và dựng lại đúng phần UI cần đổi.
5. Khi người dùng thao tác, page chỉ bắn event; tất cả xử lý thật vẫn nằm ở Bloc và domain.

Ví dụ thực tế:

- người dùng vuốt trái -> `SafeVisionModeSwiped`
- bloc đổi mode từ outdoor sang indoor
- policy tính lại danh sách detection theo indoor
- status bar đổi câu hiển thị
- bottom bar đổi nút đang chọn

