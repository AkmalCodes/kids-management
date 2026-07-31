import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/models/child.dart';
import '../../../core/models/daily_report.dart';
import '../../../core/services/child_service.dart';
import '../../../core/services/daily_report_service.dart';
import '../../../shared/util/date_display.dart';

// Parent's Reports tab: for each linked child, a feed of their daily
// reports (newest first) — the teacher's note plus any photos. Read-only.
class ChildReportsScreen extends ConsumerWidget {
  const ChildReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    return userAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (user) {
        if (user == null) return const SizedBox.shrink();
        return FutureBuilder<List<Child>>(
          future: ref.read(childServiceProvider).fetchForParent(user.id),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final children = snapshot.data!;
            if (children.isEmpty) {
              return const Center(child: Text('No children linked to your account yet.'));
            }
            return ListView(
              children: [
                for (final child in children) _ChildReportsSection(child: child),
              ],
            );
          },
        );
      },
    );
  }
}

class _ChildReportsSection extends ConsumerWidget {
  const _ChildReportsSection({required this.child});

  final Child child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(child.name, style: Theme.of(context).textTheme.titleLarge),
        ),
        FutureBuilder<List<DailyReport>>(
          future: ref.read(dailyReportServiceProvider).fetchForChild(child.id),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final reports = snapshot.data!;
            if (reports.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No reports yet.'),
              );
            }
            return Column(
              children: [for (final report in reports) _ReportCard(report: report)],
            );
          },
        ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final DailyReport report;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isoWithWeekday(report.date), style: Theme.of(context).textTheme.titleMedium),
            if (report.text.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(report.text),
            ],
            if (report.imagePaths.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: report.imagePaths.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => _ReportImage(path: report.imagePaths[i]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReportImage extends ConsumerWidget {
  const _ReportImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urlAsync = ref.watch(signedReportImageUrlProvider(path));
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 96,
        height: 96,
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
    );
  }
}
