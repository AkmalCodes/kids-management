import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/controllers/attendance_controller.dart';
import 'package:test_flutter/shared/widgets/signed_photo_thumbnail.dart';

class MockAttendanceController extends Mock implements AttendanceController {}

void main() {
  testWidgets('shows a loading indicator, then the photo once the signed URL resolves',
      (tester) async {
    final mockService = MockAttendanceController();
    when(() => mockService.getSignedPhotoUrl('child-1/2026-07-17.jpg'))
        .thenAnswer((_) async => 'https://example.supabase.co/signed/child-1/2026-07-17.jpg');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [attendanceControllerProvider.overrideWithValue(mockService)],
        child: const MaterialApp(
          home: Scaffold(
            body: SignedPhotoThumbnail(photoPath: 'child-1/2026-07-17.jpg'),
          ),
        ),
      ),
    );

    // Before the future resolves: loading state.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump();

    // After it resolves: a CircleAvatar wired to the signed URL.
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isA<NetworkImage>());
    expect(
      (avatar.backgroundImage as NetworkImage).url,
      'https://example.supabase.co/signed/child-1/2026-07-17.jpg',
    );
  });

  testWidgets('shows a broken-image icon if the signed URL fetch fails', (tester) async {
    final mockService = MockAttendanceController();
    when(() => mockService.getSignedPhotoUrl(any())).thenThrow(Exception('storage error'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [attendanceControllerProvider.overrideWithValue(mockService)],
        child: const MaterialApp(
          home: Scaffold(
            body: SignedPhotoThumbnail(photoPath: 'child-1/2026-07-17.jpg'),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });
}
