# Safe Vision - Class By Class Guide

Tài liệu này đi chậm hơn các phase trước.

Nếu các file phase trước cho bạn bức tranh tổng thể, thì file này giúp bạn nhìn từng class như một mắt xích riêng lẻ: class đó làm gì, nhận dữ liệu gì, trả ra gì, và nó đứng ở đâu trong toàn bộ dự án.

## Cách đọc file này

Đọc theo thứ tự sau sẽ dễ hiểu nhất:

1. Đi từ `main.dart` đến `app.dart` để hiểu điểm vào và cách dựng dependency.
2. Sang `SafeVisionPage` và `SafeVisionBloc` để hiểu UI và điều phối.
3. Đọc domain để hiểu luật nghiệp vụ.
4. Đọc data layer để hiểu pipeline camera, TFLite và TTS.
5. Cuối cùng ghép lại bằng luồng runtime.

## 1. Điểm vào ứng dụng

### `main()` trong `lib/main.dart`

#### Nhiệm vụ

- Khởi tạo binding của Flutter.
- Chạy widget gốc `SafeVisionApp`.

#### Cách hiểu đơn giản

Đây là công tắc bật nguồn của app.

#### Nó không làm gì

- Không mở camera.
- Không load model.
- Không xử lý detection.
- Không phát âm.

Những việc đó đều được đẩy sang các lớp phía sau.

### `SafeVisionApp` trong `lib/app.dart`

#### Nhiệm vụ

- Tạo toàn bộ dependency ở tầng dưới.
- Gắn `SafeVisionBloc` vào cây widget.
- Cấu hình theme của app.

#### Vì sao class này quan trọng

`SafeVisionApp` là nơi nối giữa “hạ tầng” và “màn hình”.

Nếu không có class này, các object như camera, detector và TTS sẽ không có nơi được tạo và đưa xuống UI một cách có kiểm soát.

#### Các object được tạo ở đây

##### `CameraDataSource`

Tạo và quản lý camera thật trên thiết bị.

##### `TfliteDetectorDataSource`

Chạy model TFLite để detect object.

##### `TtsDataSource`

Phát âm tiếng Việt.

##### `VisionRepositoryImpl`

Ghép camera + TFLite thành một API sạch cho domain.

##### `SpeechRepositoryImpl`

Ghép lớp TTS thành một API sạch cho domain.

##### `InitializeVisionUseCase`, `DetectObjectsUseCase`, `SpeakMessageUseCase`

Tách nghiệp vụ thành các hành động nhỏ, rõ nghĩa.

##### `SafeVisionBloc`

Điều phối toàn bộ trạng thái và event của màn hình Safe Vision.

#### `IoUObjectTracker` và `AudioManager`

Hai object này không được tạo ở `app.dart` mà được Bloc tạo nội bộ.

- `IoUObjectTracker` giữ tracking id ổn định qua nhiều frame.
- `AudioManager` điều tiết nhịp đọc TTS theo tracking id, priority và cooldown.

#### Vì sao `initState()` tạo object thay vì `build()`

Vì những object này cần sống lâu hơn một lần build.

Nếu tạo trong `build()`, mỗi lần rebuild UI sẽ có nguy cơ tạo lại camera hoặc TTS, gây lỗi hoặc rất tốn tài nguyên.

## 2. Presentation layer

### `SafeVisionPage`

#### Nhiệm vụ

- Hiển thị camera preview.
- Hiển thị overlay detection.
- Nhận thao tác người dùng.
- Gửi event lên Bloc.

#### Dữ liệu đi qua class này

- Nhận `SafeVisionBloc` từ context.
- Không tự tính nghiệp vụ.
- Chỉ đọc state và render.

#### `initState()`

- Gửi `SafeVisionStarted`.

Nghĩa là page chỉ nói: “Hãy bắt đầu chạy hệ thống.”

#### `build()`

Page ghép màn hình bằng `Stack`.

Lý do dùng `Stack` là vì có nhiều lớp chồng lên nhau:

- nền là preview camera
- trên preview là detection box
- trên nữa là status bar
- góc phải là nút đổi camera
- dưới cùng là thanh chọn mode

#### `GestureDetector`

`GestureDetector` bắt thao tác vuốt ngang.

Khi vuốt:

- nếu vuốt sang trái, app đi sang mode tiếp theo
- nếu vuốt sang phải, app quay lại mode trước

Đây là một cách điều khiển nhanh, đặc biệt hữu ích với người dùng cần thao tác ít bước.

### `BlocBuilder`

`BlocBuilder` là cầu nối giữa state và widget.

Mỗi `BlocBuilder` ở page chỉ nghe một phần state:

- một cái nghe camera controller và `isInitializing`
- một cái nghe detections
- một cái nghe `statusText` và `mode`
- một cái nghe `isFrontCamera`

#### Vì sao chia nhỏ

Để tránh rebuild toàn bộ màn hình khi chỉ một phần nhỏ thay đổi.

Ví dụ:

- detection đổi thì không cần vẽ lại status bar
- status bar đổi thì không cần rebuild preview camera
- camera trước/sau đổi thì không cần thay overlay logic

### `TopStatusBar`

#### Nhiệm vụ

- Hiển thị mode hiện tại.
- Hiển thị `statusText`.

#### Nó dùng gì

- `mode` để biết app đang ở outdoor, indoor hay tutorial.
- `statusText` để hiển thị câu tóm tắt ngắn.

### `BottomActionBar`

#### Nhiệm vụ

- Hiển thị 3 nút mode.
- Báo lại mode người dùng chọn.

#### Nó không làm gì

- Không tự đổi mode.
- Không tự tính policy.
- Không tự phát âm.

Nó chỉ báo “người dùng muốn chuyển sang mode này”.

### `DetectionPainter`

#### Nhiệm vụ

- Vẽ hộp detection.
- Vẽ nhãn tiếng Việt + score.

#### Input

- Một list `Detection` đã được Bloc xử lý và lọc.

#### Output

- Hình ảnh overlay trên camera preview.

### `LoadingPanel`

#### Nhiệm vụ

- Cho người dùng biết app đang khởi tạo.

#### Khi nào hiện

- Lúc camera chưa sẵn sàng.
- Lúc model hoặc stream chưa xong.

## 3. Bloc và event/state

### `SafeVisionBloc`

#### Nhiệm vụ tổng quát

Bloc là bộ não điều phối.

Nó không trực tiếp làm camera hay AI, nhưng nó quyết định:

- khi nào khởi tạo
- khi nào nhận frame
- khi nào detect
- khi nào đổi mode
- khi nào đổi camera
- khi nào phát âm

#### Các dependency của Bloc

- `InitializeVisionUseCase`
- `DetectObjectsUseCase`
- `SpeakMessageUseCase`
- `VisionRepository`
- `SpeechRepository`

Bloc giữ cả use case và repository vì nó vừa cần mức nghiệp vụ, vừa cần trạng thái trực tiếp của hệ thống.

#### Event mà Bloc nhận

##### `SafeVisionStarted`

Bắt đầu toàn bộ hệ thống.

##### `CameraFrameReceived`

Nhận một frame camera mới để phân tích.

##### `SafeVisionModeChanged`

Người dùng chọn một mode cụ thể.

##### `SafeVisionModeSwiped`

Người dùng vuốt để chuyển mode.

##### `CameraLensToggled`

Người dùng đổi camera trước/sau.

#### State mà Bloc giữ

##### `isInitializing`

Báo app đang khởi tạo hoặc đổi camera.

##### `statusText`

Câu tóm tắt trạng thái hiện tại.

##### `isFrontCamera`

Cho biết đang dùng camera trước hay sau.

##### `mode`

Mode hiện tại của app.

##### `rawDetections`

Kết quả detection gốc trước khi policy lọc.

##### `detections`

Danh sách detection đã được lọc theo mode.

##### `cameraController`

Controller của camera đang hoạt động.

##### `errorMessage`

Thông báo lỗi nếu có sự cố.

#### Cách Bloc vận hành theo từng bước

1. Nhận event.
2. Gọi use case hoặc repository.
3. Nhận kết quả.
4. Dùng policy và tracker để lọc hoặc ổn định dữ liệu.
5. Dùng `AudioManager` để quyết định có cần phát âm không.
6. Cập nhật state.
7. UI tự rebuild theo state mới.

#### Các biến nội bộ quan trọng

##### `_frameThrottleMs`

Giới hạn tốc độ nhận frame để tránh quá tải.

##### `_ttsCooldownMs`

Giới hạn khoảng thời gian giữa các câu nói.

##### `_isProcessingFrame`

Chặn xử lý chồng chéo nhiều frame cùng lúc.

##### `_lastFrameAcceptedAt`

Mốc thời gian nhận frame gần nhất.

##### `_objectTracker`

Giữ tracking id ổn định cho detections qua nhiều frame.

##### `_audioManager`

Điều tiết nhịp đọc TTS theo tracking id và mức độ cảnh báo.

##### `_labelMetadata`

Bản đồ nhãn tiếng Việt và bucket cảnh báo lấy từ asset.

### `SafeVisionState`

#### Nhiệm vụ

Lưu toàn bộ trạng thái hiện tại của màn hình.

#### Vì sao state quan trọng

UI của app này không tự giữ logic phức tạp. Nó chỉ vẽ theo state.

Vì vậy, muốn hiểu app đang làm gì, bạn chỉ cần nhìn state:

- đang khởi tạo hay chưa
- đang ở mode nào
- camera trước hay sau
- có lỗi hay không
- detections hiện tại là gì

## 4. Domain và policy

### `SafeVisionPolicy`

#### Vai trò

Là nơi quyết định luật nghiệp vụ cho detection, status text và speech payload.

#### Nó xử lý gì

- lọc detections theo mode
- xác định object nào nằm trong vùng nguy hiểm
- tạo câu trạng thái cho UI
- tạo nội dung giọng nói cho TTS

### `IoUObjectTracker`

#### Vai trò

Giữ tracking id và bounding box ổn định qua nhiều frame.

#### Tại sao cần tracker riêng

Vì camera trả frame liên tục, còn detection thô có thể dao động giữa các frame. Tracker giúp cùng một vật thể vẫn được nhận ra là cùng một thực thể.

### `AudioManager`

#### Vai trò

Quyết định khi nào cần nói, khi nào cần ngắt câu cũ, và khi nào cần im lặng để tránh spam.

#### Tại sao cần lớp này

Nếu chỉ dựa vào `SpeakMessageUseCase`, app sẽ rất dễ đọc lặp cùng một cảnh báo nhiều lần liên tiếp.

### `Detection`

#### Vai trò

Model dữ liệu của một object đã được nhận diện.

#### Các property chính

- `label`
- `score`
- `left`, `top`, `right`, `bottom`
- `trackingId`
- `areaRatio`
- `estimatedDistance`

### `SafeVisionMode`

#### Vai trò

Định nghĩa 3 mode của app:

- `outdoor`
- `indoor`
- `tutorial`

### `VisionRepository`

#### Vai trò

Là hợp đồng cho tầng vision.

#### Nó che giấu gì

- cách camera được mở
- cách TFLite chạy
- cách rotation được tính

### `SpeechRepository`

#### Vai trò

Là hợp đồng cho tầng speech/TTS.

#### Nó che giấu gì

- cách cấu hình tiếng Việt
- cách phát âm
- cách dừng phát âm
- cách dọn tài nguyên TTS

## 5. Data layer

### `VisionRepositoryImpl`

#### Vai trò

Là nơi ghép camera + TFLite thành một pipeline hoàn chỉnh.

#### Tại sao không để Bloc làm việc này

Vì Bloc cần giữ vai trò điều phối trạng thái, không nên gánh toàn bộ chi tiết kỹ thuật của AI và camera.

### `CameraDataSource`

#### Vai trò

Quản lý camera thật trên thiết bị.

#### Đầu vào và đầu ra

- Đầu vào: yêu cầu khởi tạo hoặc đổi camera.
- Đầu ra: `CameraController` sẵn sàng để hiển thị preview và stream frame.

### `TfliteDetectorDataSource`

#### Vai trò

Chạy suy luận TFLite trong isolate riêng để tránh block UI.

#### Hai việc quan trọng

- load labels và model từ asset
- nhận `CameraImage` rồi trả về danh sách `Detection`

### `TtsDataSource`

#### Vai trò

Bọc `FlutterTts`, cấu hình tiếng Việt và điều khiển phát âm.

### `SpeechRepositoryImpl`

#### Vai trò

Gom logic từ `TtsDataSource` thành API sạch hơn cho domain.

## 6. Cách các class tương tác

### Luồng runtime ngắn gọn

1. `main()` mở app.
2. `SafeVisionApp` dựng dependency.
3. `SafeVisionBloc` nhận event khởi động.
4. `VisionRepositoryImpl` mở camera và load TFLite.
5. `SafeVisionPage` nhận state và render UI.
6. Camera stream trả frame vào Bloc.
7. Bloc detect, tracker, policy và audio manager xử lý.
8. UI và TTS cập nhật theo state mới.

### Câu nhớ nhanh

UI chỉ gửi ý định, Bloc điều phối, domain áp luật và nhịp đọc, data làm việc nặng.
