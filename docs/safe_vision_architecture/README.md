# Safe Vision Architecture

Tài liệu này chia kiến trúc dự án Safe Vision thành từng phase để đọc từng lớp theo đúng luồng hoạt động của app.

Mục tiêu của bộ tài liệu này không chỉ là liệt kê class, mà là giúp bạn hiểu:

- class nào chịu trách nhiệm gì
- dữ liệu đi qua từng tầng như thế nào
- vì sao project được tách thành nhiều lớp thay vì gom hết vào một nơi
- khi người dùng bấm nút, vuốt màn hình, hoặc camera trả frame thì hệ thống phản ứng ra sao

## Cách đọc

1. Đọc Phase 1 để hiểu app khởi động và tạo dependency như thế nào.
2. Đọc Phase 2 để hiểu UI nhận state từ Bloc và phát sinh event ra sao.
3. Đọc Phase 3 để hiểu lớp domain, policy và quy tắc xử lý nghiệp vụ.
4. Đọc Phase 4 để hiểu tầng data: camera, TFLite, TTS.
5. Đọc Phase 5 để ghép toàn bộ vòng đời từ mở app đến cảnh báo giọng nói.

## Các file

- [Phase 1 - Khởi động và dependency injection](phase-1-bootstrap.md)
- [Phase 2 - Presentation layer và tương tác UI](phase-2-presentation.md)
- [Phase 3 - Domain layer, policy và nghiệp vụ](phase-3-domain.md)
- [Phase 4 - Data layer và xử lý AI/camera/TTS](phase-4-data.md)
- [Phase 5 - Luồng chạy end-to-end](phase-5-runtime-flow.md)
- [Class by class guide](class-by-class-guide.md)

## Tóm tắt nhanh

- `main.dart` chỉ là điểm vào Flutter.
- `app.dart` tạo toàn bộ dependency và đưa `SafeVisionBloc` vào cây widget.
- `SafeVisionPage` chỉ quan sát state và bắn event khi người dùng thao tác.
- `SafeVisionBloc` là bộ điều phối trung tâm giữa UI, domain và data.
- `SafeVisionPolicy` quyết định cái gì được giữ lại, cái gì được nói ra.
- `IoUObjectTracker` giữ cho detection ổn định qua nhiều frame.
- `AudioManager` điều tiết nhịp đọc TTS để tránh lặp câu quá dày.
- `VisionRepositoryImpl` ghép camera + TFLite thành pipeline detection ở tầng data.
- `TtsDataSource` chịu trách nhiệm phát âm tiếng Việt.

## Gợi ý học theo thứ tự

Nếu bạn muốn hiểu thật chắc, hãy đọc theo 3 vòng:

1. Đọc Phase 1 và Phase 2 để hiểu app khởi động và UI bắn event.
2. Đọc Phase 3 để hiểu luật nghiệp vụ, mode và giọng nói.
3. Đọc Phase 4 và Phase 5 để hiểu pipeline xử lý thực sự từ camera đến cảnh báo.

