import 'package:flutter/material.dart';

/// IndexedStack that builds each child on FIRST activation and keeps it alive
/// afterwards — panel state (activity pagination, ledger filter, the #204
/// once-per-entry review sheet guard) survives tab switches, while inactive
/// never-visited panels cost nothing.
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
  final Set<int> _built = {};

  @override
  Widget build(BuildContext context) {
    _built.add(widget.index);
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          if (_built.contains(i))
            widget.children[i]
          else
            const SizedBox.shrink(),
      ],
    );
  }
}
