import 'package:flutter/material.dart';

// Shows one of [children] at a time, like the role shells' tab bodies.
//
// Why not just `body: pages[index]`? That throws the old page away and
// builds the new one from scratch on every tab tap, re-running its
// initState (which fetches from Supabase). The build lands on the same frame
// the bottom-nav animation starts, so the animation visibly stalls, and every
// revisit shows a loader again.
//
// Why not a plain IndexedStack? It keeps every page alive, but builds ALL of
// them up front, so logging in would fire every tab's network requests at
// once, even for tabs the user never opens.
//
// This is the middle ground: a page is built the first time its tab is
// shown, then kept alive (hidden) inside an IndexedStack. Switching back is
// instant and keeps scroll position and loaded data.
//
// Trade-off: a kept page doesn't refetch just because you came back to it.
// Data from realtime streams stays live anyway; screens that load once in
// initState refresh through their own pull-to-refresh / after-edit reloads.
class LazyIndexedStack extends StatefulWidget {
  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  // Which pages have been shown at least once. Lives in State, so it
  // survives rebuilds when the shell changes `index`.
  late final List<bool> _visited =
      List.generate(widget.children.length, (i) => i == widget.index);

  @override
  Widget build(BuildContext context) {
    // Mark the current page as visited before building. Done in build (not
    // didUpdateWidget) because build always runs after an index change.
    _visited[widget.index] = true;
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          // Never-visited pages are an empty placeholder: no State, no
          // initState, no network calls until the user opens that tab.
          _visited[i] ? widget.children[i] : const SizedBox.shrink(),
      ],
    );
  }
}
