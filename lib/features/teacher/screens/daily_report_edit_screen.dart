import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/models/child.dart';
import '../../../core/models/daily_report.dart';
import '../../../core/services/daily_report_service.dart';
import '../../../core/services/photo_capture_service.dart';
import '../../../shared/widgets/avatar_source_sheet.dart';

// Teacher writes/edits the daily report for one child on one day (today).
// One report per child per day: opens the existing one if present, else a
// blank form. Photos are uploaded to the report bucket as they're added and
// the text + image paths are persisted on Save.
class DailyReportEditScreen extends ConsumerStatefulWidget {
  const DailyReportEditScreen({super.key, required this.child});

  final Child child;

  @override
  ConsumerState<DailyReportEditScreen> createState() => _DailyReportEditScreenState();
}

class _DailyReportEditScreenState extends ConsumerState<DailyReportEditScreen> {
  final _textController = TextEditingController();
  final _today = DateTime.now().toIso8601String().substring(0, 10);

  late Future<DailyReport?> _existingFuture;
  DailyReport? _existing;
  List<String> _imagePaths = [];
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _existingFuture = _load();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<DailyReport?> _load() async {
    final report = await ref
        .read(dailyReportServiceProvider)
        .fetchForChildAndDate(widget.child.id, _today);
    if (report != null) {
      _existing = report;
      _textController.text = report.text;
      _imagePaths = [...report.imagePaths];
    }
    _loaded = true;
    return report;
  }

  Future<void> _addPhoto() async {
    final source = await showAvatarSourceSheet(context);
    if (source == null) return;
    final capture = ref.read(photoCaptureServiceProvider);
    final photo = source == AvatarSource.gallery
        ? await capture.pickFromGallery()
        : await capture.captureFromCamera();
    if (photo == null) return;
    try {
      final path = await ref.read(dailyReportServiceProvider).uploadReportImage(
            childId: widget.child.id,
            date: _today,
            photo: photo,
          );
      if (!mounted) return;
      setState(() => _imagePaths = [..._imagePaths, path]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add photo: $e')),
      );
    }
  }

  void _removePhoto(String path) {
    setState(() => _imagePaths = _imagePaths.where((p) => p != path).toList());
  }

  Future<void> _save() async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(dailyReportServiceProvider).saveReport(
            childId: widget.child.id,
            teacherId: user.id,
            centerId: widget.child.centerId,
            date: _today,
            text: _textController.text.trim(),
            imagePaths: _imagePaths,
            actorUid: user.id,
            existingId: _existing?.id,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save report: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.child.name} — daily report')),
      body: FutureBuilder<DailyReport?>(
        future: _existingFuture,
        builder: (context, snapshot) {
          if (!_loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(_today, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: _textController,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: "How was the child's day?",
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Photos', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addPhoto,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Add'),
                  ),
                ],
              ),
              if (_imagePaths.isEmpty)
                const Text('No photos yet.')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final path in _imagePaths)
                      _ReportImageThumb(path: path, onRemove: () => _removePhoto(path)),
                  ],
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save report'),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Square thumbnail for a report image (signed URL) with a remove button.
class _ReportImageThumb extends ConsumerWidget {
  const _ReportImageThumb({required this.path, required this.onRemove});

  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urlAsync = ref.watch(signedReportImageUrlProvider(path));
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 88,
            height: 88,
            child: urlAsync.when(
              loading: () => const ColoredBox(
                color: Color(0x11000000),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (_, _) => const ColoredBox(
                color: Color(0x11000000),
                child: Icon(Icons.broken_image_outlined),
              ),
              data: (url) => Image.network(url, fit: BoxFit.cover),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              padding: const EdgeInsets.all(2),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
