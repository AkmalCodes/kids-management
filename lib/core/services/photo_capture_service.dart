import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

// Thin wrapper around ImagePicker so screens depend on an injectable
// service instead of the static picker directly — the actual native
// camera UI can't be driven from a widget test (same category of
// untestable native interaction as showTimePicker/showDatePicker
// elsewhere in this app), so this boundary is what tests mock.
class PhotoCaptureService {
  final ImagePicker _picker;

  PhotoCaptureService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  Future<XFile?> captureFromCamera() {
    return _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
  }
}

final photoCaptureServiceProvider = Provider<PhotoCaptureService>(
  (ref) => PhotoCaptureService(),
);
