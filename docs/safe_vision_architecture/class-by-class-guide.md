# Safe Vision - Class By Class Guide

Tài liệu này đi chậm hơn các phase trước.

Nếu các file phase trước cho bạn bức tranh tổng thể, thì file này giúp bạn nhìn từng class như một mắt xích riêng lẻ: class đó làm gì, nhận dữ liệu gì, trả ra gì, và nó đứng ở đâu trong toàn bộ dự án.

## Cách đọc file này

Đọc theo thứ tự sau sẽ dễ hiểu nhất:

1. Đi từ `main.dart` đến `app.dart` để hiểu điểm vào và cách dựng dependency.
2. Sang `SafeVisionPage` và `SafeVisionBloc` để hiểu UI và điều phối.
3. Đọc domain để hiểu luật nghiệp vụ.
4. Đọc data layer để hiểu pipeline camera, ML, TFLite, TTS.
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

Nếu không có class này, các object như camera, tracker, detector, TTS sẽ không có nơi được tạo và đưa xuống UI một cách có kiểm soát.

#### Các object được tạo ở đây

##### `CameraDataSource`

Tạo và quản lý camera thật trên thiết bị.

##### `MlKitTrackerDataSource`

Dùng để track vật thể và tìm vùng ROI của người.

##### `TfliteDetectorDataSource`

Chạy model TFLite để detect object.

##### `TtsDataSource`

Phát âm tiếng Việt.

##### `VisionRepositoryImpl`

Ghép camera + tracker + detector thành một pipeline nhận diện hoàn chỉnh.

##### `SpeechRepositoryImpl`

Ghép lớp TTS thành một API sạch cho domain.

##### `InitializeVisionUseCase`, `DetectObjectsUseCase`, `SpeakMessageUseCase`

Tách nghiệp vụ thành các hành động nhỏ, rõ nghĩa.

##### `SafeVisionBloc`

Điều phối toàn bộ trạng thái và event của màn hình Safe Vision.

#### Vì sao initState() tạo object thay vì build()

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

- một cái nghe camera controller và isInitializing
- một cái nghe detections
- một cái nghe statusText và mode
- một cái nghe isFrontCamera

#### Vì sao chia nhỏ

Để tránh rebuild toàn bộ màn hình khi chỉ một phần nhỏ thay đổi.

Ví dụ:

- detection đổi thì không cần vẽ lại status bar
- status bar đổi thì không cần rebuild preview camera
- camera trước/sau đổi thì không cần thay overlay logic

### `TopStatusBar`

#### Nhiệm vụ

- Hiển thị mode hiện tại.
- Hiển thị statusText.

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
4. Dùng policy để lọc hoặc tạo câu nói.
5. Cập nhật state.
6. UI tự rebuild theo state mới.

#### Các biến nội bộ quan trọng

##### `_frameThrottleMs`

Giới hạn tốc độ nhận frame để tránh quá tải.

##### `_ttsCooldownMs`

Giới hạn khoảng thời gian giữa các câu nói.

##### `_isProcessingFrame`

Chặn xử lý chồng chéo nhiều frame cùng lúc.

##### `_lastFrameAcceptedAt`

Theo dõi thời điểm frame gần nhất được nhận.

##### `_lastSmartTtsAt`

Theo dõi thời điểm gần nhất app phát âm.

##### `_labelMetadata`

Metadata tiếng Việt và bucket của từng label.

##### `_lastWarningKeys`

Theo dõi cảnh báo đã nói gần nhất.

##### `_lastSpokenMessageKey`

Giúp tránh lặp lại câu nói y hệt.

### `SafeVisionEvent`

#### Vai trò

Là lớp gốc cho toàn bộ event của feature.

Tách event thành từng lớp con giúp code rõ hơn:

- event nào dùng để khởi động
- event nào dùng để xử lý frame
- event nào dùng để đổi mode
- event nào dùng để đổi camera

### `SafeVisionState`

#### Vai trò

Lưu toàn bộ trạng thái hiện tại của màn hình.

#### Vì sao state quan trọng

UI của app này không tự giữ logic phức tạp. Nó chỉ vẽ theo state.

Vì vậy, muốn hiểu app đang làm gì, bạn chỉ cần nhìn state:

- đang khởi tạo hay chưa
- đang ở mode nào
- có detection nào không
- camera trước hay sau
- có lỗi hay không

#### `copyWith()`

Dùng để tạo state mới từ state cũ mà chỉ đổi một vài trường.

Đây là cách Bloc hoạt động rất điển hình: không sửa state cũ, mà tạo state mới.

## 4. Domain layer

### `InitializeVisionUseCase`

#### Nhiệm vụ

- Gọi `visionRepository.initializeCamera()`.

#### Ý nghĩa

Đây là lớp nói với hệ thống rằng: “hãy chuẩn bị camera và các thành phần vision”.

### `DetectObjectsUseCase`

#### Nhiệm vụ

- Gọi `visionRepository.detect(image)`.

#### Ý nghĩa

Đây là lớp nói: “hãy phân tích frame này và trả về các vật thể nhìn thấy”.

### `SpeakMessageUseCase`

#### Nhiệm vụ

- cấu hình TTS
- phát âm
- dừng âm thanh
- kiểm tra đang nói hay không

#### Ý nghĩa

Bloc không cần biết TTS là package nào. Nó chỉ cần một lớp nói “hãy đọc câu này”.

### `SafeVisionPolicy`

Đây là lớp quan trọng nhất trong domain.

#### Vai trò của policy

Policy quyết định:

- detection nào được giữ
- detection nào bị bỏ qua
- câu nào sẽ hiển thị
- câu nào sẽ được nói ra

#### Tại sao phải có policy riêng

Vì nếu không có policy, các rule nghiệp vụ sẽ bị rải ở nhiều nơi:

- một ít ở bloc
- một ít ở widget
- một ít ở repository

Khi đó sửa một rule sẽ rất khó.

#### Ba hàm chính

##### `filterDetectionsForMode()`

Lọc detections theo mode.

##### `buildStatusText()`

Tạo câu trạng thái ngắn cho UI.

##### `buildSpeechPayload()`

Tạo nội dung giọng nói cho TTS.

### `Detection`

#### Vai trò

Đại diện cho một object đã detect được.

#### Nó chứa gì

- tên object
- độ tin cậy
- tọa độ box

#### Các helper property

- `width`
- `height`
- `areaRatio`
- `centerX`

Những helper này phục vụ tính toán nguy hiểm và hiển thị.

### `SafeVisionMode`

#### Vai trò

Xác định 3 chế độ hoạt động:

- outdoor
- indoor
- tutorial

#### Ý nghĩa thực tế

- outdoor: nhấn mạnh an toàn đường đi
- indoor: nhấn mạnh tìm vật dụng
- tutorial: nhấn mạnh học cách sử dụng

### `VisionRepository`

#### Vai trò

Là hợp đồng cho tầng vision.

#### Nó che giấu gì

- cách camera được mở
- cách TFLite chạy
- cách ML Kit track object

### `SpeechRepository`

#### Vai trò

Là hợp đồng cho tầng speech/TTS.

## 5. Data layer

### `VisionRepositoryImpl`

#### Vai trò

Là nơi ghép camera + ML Kit + TFLite thành một pipeline hoàn chỉnh.

#### Tại sao không để Bloc làm việc này

Vì Bloc cần giữ vai trò điều phối trạng thái, không nên gánh toàn bộ chi tiết kỹ thuật của AI và camera.

#### `initializeCamera()`

Khởi tạo camera và load các thành phần model.

#### `detect()`

Nhận một frame rồi trả về danh sách detections.

#### `_detectHybrid()`

Là pipeline chính:

1. track object
2. tìm ROI
3. chạy detector theo chu kỳ
4. ghép label với tracking
5. trả kết quả cuối

#### `_fuseTrackedWithLabels()`

Ghép box theo tracking với label tốt nhất.

#### `_bestMatch()`

Tìm detection phù hợp nhất với một box track.

#### `_nonMaxSuppression()`

Loại box trùng lặp.

### `CameraDataSource`

#### Vai trò

Quản lý camera thật.

#### Các việc chính

- mở camera
- đổi camera
- bắt đầu stream
- dừng và giải phóng camera

#### Đầu ra quan trọng

- `CameraController`

### `MlKitTrackerDataSource`

#### Vai trò

Là lớp chuyên làm tracking và tìm ROI.

#### `load()`

Khởi tạo detector.

#### `track()`

Lấy box tracking của object đang xuất hiện.

#### `detectPersonRois()`

Tìm vùng người để tối ưu việc detect tiếp theo.

### `TfliteDetectorDataSource`

#### Vai trò

Chạy model TFLite để phát hiện object.

#### Tại sao phức tạp hơn các lớp khác

Vì nó phải:

- nạp model
- chạy isolate
- xử lý ảnh YUV
- trả result theo request id

#### `load()`

Nạp labels và model, khởi tạo worker isolate.

#### `detect()`

Chạy detect trên toàn ảnh.

#### `detectInRoi()`

Chạy detect trong vùng nhỏ hơn.

#### `_requestDetection()`

Gửi frame sang isolate để xử lý.

### `TtsDataSource`

#### Vai trò

Phát âm tiếng Việt.

#### Các việc chính

- set language
- set pitch
- set speech rate
- speak
- stop

#### Tại sao phải có `_isSpeaking`

Để Bloc biết TTS đang bận hay không.

### `MlKitInputImageConverter`

#### Vai trò

Chuyển `CameraImage` sang `InputImage` cho ML Kit.

#### Tại sao cần converter riêng

Vì camera trả ảnh thô theo format riêng, còn ML Kit cần input theo format khác.

#### Hai việc quan trọng

- đổi format ảnh
- tính rotation đúng

### `SpeechRepositoryImpl`

#### Vai trò

Lớp mỏng bọc TTS datasource.

#### Lợi ích

Giữ cho domain chỉ nhìn thấy interface `SpeechRepository`.

## 6. Luồng tổng hợp dễ hiểu

Hãy nhớ chuỗi sau:

1. UI mở ra.
2. Page bắn event start.
3. Bloc khởi tạo camera, TTS và model.
4. Camera bắt đầu đẩy frame.
5. Bloc nhận frame và gọi detect.
6. Repository ghép tracker + detector.
7. Policy lọc kết quả theo mode.
8. UI hiển thị bounding box và status.
9. TTS nói nếu có cảnh báo phù hợp.

## 7. Một câu chốt để nhớ kiến trúc này

Nếu phải nhớ ít thôi, hãy nhớ câu này:

- UI chỉ nhận lệnh và hiển thị
- Bloc điều phối
- Domain quyết định luật
- Data làm việc nặng

Đây chính là xương sống của dự án Safe Vision.
