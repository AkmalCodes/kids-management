import 'package:flutter/material.dart';

// A centred message ("No children yet.") that can still be pulled down to
// refresh when it sits inside a RefreshIndicator.
//
// Why it's needed: RefreshIndicator only reacts to a scrollable being
// over-scrolled at the top. A plain `Center(child: Text(...))` doesn't
// scroll, so an empty screen could never be refreshed. That matters because
// tab pages are kept alive (see LazyIndexedStack): an empty list stays empty
// until the user pulls, e.g. after enrolling a child from another tab.
//
// Trick: a scroll view that may always scroll
// (AlwaysScrollableScrollPhysics), whose content is forced to be at least as
// tall as the space available, so the message stays vertically centred.
class RefreshableMessage extends StatelessWidget {
  const RefreshableMessage(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: Text(message)),
        ),
      ),
    );
  }
}
