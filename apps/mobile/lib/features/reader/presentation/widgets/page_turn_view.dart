import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A book-like page surface with touch, pointer, and keyboard navigation.
///
/// The animation is deliberately presentation-only. Callers retain ownership of
/// logical document positions and provide page content through [itemBuilder].
class PageTurnView extends StatefulWidget {
  const PageTurnView({
    required this.itemCount,
    required this.itemBuilder,
    this.initialPage = 0,
    this.onPageChanged,
    this.turnDuration = const Duration(milliseconds: 520),
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;
  final Duration turnDuration;

  @override
  State<PageTurnView> createState() => _PageTurnViewState();
}

class _PageTurnViewState extends State<PageTurnView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turnController;
  late int _pageIndex;
  int? _targetPage;
  bool _forward = true;
  double _dragDistance = 0;
  double _viewportWidth = 1;

  @override
  void initState() {
    super.initState();
    _pageIndex = _clampedPage(widget.initialPage);
    _turnController = AnimationController(
      vsync: this,
      duration: widget.turnDuration,
    )..addStatusListener(_handleAnimationStatus);
  }

  @override
  void didUpdateWidget(PageTurnView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.turnDuration != widget.turnDuration) {
      _turnController.duration = widget.turnDuration;
    }
    // An externally requested page (a bookmark jump, a restored position, or a
    // re-paginated layout) replaces whatever is on screen, including a turn in
    // flight.
    if (widget.initialPage != oldWidget.initialPage) {
      _pageIndex = _clampedPage(widget.initialPage);
      _abandonTurn();
      return;
    }

    // The page count grows as the document is measured incrementally, so it
    // changes constantly while reading a long book. That must not disturb the
    // current page or cancel a turn: cancelling one silently swallows the
    // reader's tap, because `onPageChanged` only fires when a turn completes.
    // Only an index that no longer exists forces a correction.
    if (widget.itemCount != oldWidget.itemCount) {
      final clamped = _clampedPage(_pageIndex);
      final target = _targetPage;
      if (clamped != _pageIndex) {
        _pageIndex = clamped;
        _abandonTurn();
      } else if (target != null && target >= widget.itemCount) {
        _abandonTurn();
      }
    }
  }

  /// Drops a turn in progress without reporting it, leaving [_pageIndex] as the
  /// visible page.
  void _abandonTurn() {
    _targetPage = null;
    _dragDistance = 0;
    _turnController
      ..stop()
      ..value = 0;
  }

  @override
  void dispose() {
    _turnController.dispose();
    super.dispose();
  }

  int _clampedPage(int value) {
    if (widget.itemCount <= 0) return 0;
    return value.clamp(0, widget.itemCount - 1);
  }

  bool get _canGoBack => _pageIndex > 0;
  bool get _canGoForward => _pageIndex + 1 < widget.itemCount;

  void _handleAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _targetPage == null) return;
    final target = _targetPage!;
    setState(() {
      _pageIndex = target;
      _targetPage = null;
      _dragDistance = 0;
      _turnController.value = 0;
    });
    widget.onPageChanged?.call(target);
  }

  void _changePage(int delta) {
    if (_targetPage != null || widget.itemCount <= 1) return;
    final target = _pageIndex + delta;
    if (target < 0 || target >= widget.itemCount) return;

    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _pageIndex = target);
      widget.onPageChanged?.call(target);
      return;
    }

    setState(() {
      _forward = delta > 0;
      _targetPage = target;
      _dragDistance = 0;
      _turnController.value = 0;
    });
    _turnController.animateTo(1, curve: Curves.easeInOutCubic);
  }

  void _onDragStart(DragStartDetails details) {
    if (_targetPage != null) return;
    _dragDistance = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (widget.itemCount <= 1) return;
    _dragDistance += details.delta.dx;
    if (_dragDistance == 0) return;

    // Reduced motion keeps the gesture but does not render an interactive
    // perspective fold. The completed drag is committed instantly in end.
    if (MediaQuery.disableAnimationsOf(context)) return;

    final forward = _dragDistance < 0;
    if ((forward && !_canGoForward) || (!forward && !_canGoBack)) {
      _turnController.value = 0;
      return;
    }

    final target = _pageIndex + (forward ? 1 : -1);
    setState(() {
      _forward = forward;
      _targetPage = target;
      _turnController.value = (_dragDistance.abs() / (_viewportWidth * 0.72))
          .clamp(0.0, 1.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (MediaQuery.disableAnimationsOf(context)) {
      final velocity = details.primaryVelocity ?? 0;
      final distanceCommits =
          _dragDistance.abs() >= (_viewportWidth * 0.23).clamp(36.0, 160.0);
      final velocityCommits = velocity.abs() > 420;
      if (distanceCommits || velocityCommits) {
        final forward = _dragDistance != 0 ? _dragDistance < 0 : velocity < 0;
        _changePage(forward ? 1 : -1);
      }
      _dragDistance = 0;
      return;
    }

    final target = _targetPage;
    if (target == null) return;
    final velocity = details.primaryVelocity ?? 0;
    final commitsByVelocity = _forward ? velocity < -420 : velocity > 420;
    final shouldCommit = _turnController.value >= 0.32 || commitsByVelocity;

    if (shouldCommit) {
      _turnController.animateTo(1, curve: Curves.easeOutCubic);
    } else {
      _turnController.animateBack(0, curve: Curves.easeOutCubic).whenComplete(
        () {
          if (!mounted) return;
          setState(() {
            _targetPage = null;
            _dragDistance = 0;
          });
        },
      );
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.pageDown ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _changePage(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.pageUp) {
      _changePage(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount <= 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportWidth = constraints.maxWidth;
        final edgeDragWidth = math.min(
          30.0,
          math.max(0.0, constraints.maxWidth / 2),
        );
        return Focus(
          autofocus: true,
          onKeyEvent: _onKeyEvent,
          child: Semantics(
            label: 'Page ${_pageIndex + 1} of ${widget.itemCount}',
            liveRegion: true,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildPageSurface(_pageIndex),
                if (_targetPage != null)
                  AnimatedBuilder(
                    animation: _turnController,
                    builder: (context, _) => _buildTurn(
                      progress: Curves.easeInOut.transform(
                        _turnController.value,
                      ),
                    ),
                  ),
                _PageEdgeDragRegion(
                  hitRegionKey: const ValueKey('page-edge-left'),
                  alignment: Alignment.centerLeft,
                  width: edgeDragWidth,
                  onHorizontalDragStart: _onDragStart,
                  onHorizontalDragUpdate: _onDragUpdate,
                  onHorizontalDragEnd: _onDragEnd,
                ),
                _PageEdgeDragRegion(
                  hitRegionKey: const ValueKey('page-edge-right'),
                  alignment: Alignment.centerRight,
                  width: edgeDragWidth,
                  onHorizontalDragStart: _onDragStart,
                  onHorizontalDragUpdate: _onDragUpdate,
                  onHorizontalDragEnd: _onDragEnd,
                ),
                _PageNavigationButton(
                  alignment: Alignment.centerLeft,
                  tooltip: 'Previous page',
                  icon: Icons.chevron_left_rounded,
                  enabled: _canGoBack && _targetPage == null,
                  onPressed: () => _changePage(-1),
                ),
                _PageNavigationButton(
                  alignment: Alignment.centerRight,
                  tooltip: 'Next page',
                  icon: Icons.chevron_right_rounded,
                  enabled: _canGoForward && _targetPage == null,
                  onPressed: () => _changePage(1),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPageSurface(int index) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: widget.itemBuilder(context, index),
    );
  }

  Widget _buildTurn({required double progress}) {
    final target = _targetPage!;
    final current = _buildPageSurface(_pageIndex);
    final incoming = _buildPageSurface(target);
    final angle = progress * math.pi / 2;
    final rotation = _forward ? -angle : angle;
    final alignment = _forward ? Alignment.centerRight : Alignment.centerLeft;
    final shadowAlignment = _forward
        ? Alignment.centerRight
        : Alignment.centerLeft;

    return Stack(
      key: const ValueKey('page-turn-perspective'),
      fit: StackFit.expand,
      children: [
        incoming,
        Transform(
          alignment: alignment,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0018)
            ..rotateY(rotation),
          child: Stack(
            fit: StackFit.expand,
            children: [
              current,
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: shadowAlignment,
                    end: _forward
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    colors: [
                      Colors.black.withValues(alpha: 0.24 * progress),
                      Colors.black.withValues(alpha: 0.06 * progress),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.16, 0.58],
                  ),
                ),
              ),
              Align(
                alignment: shadowAlignment,
                child: Container(
                  width: 3 + (9 * progress),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.48 * progress),
                        Colors.black.withValues(alpha: 0.18 * progress),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PageEdgeDragRegion extends StatelessWidget {
  const _PageEdgeDragRegion({
    required this.hitRegionKey,
    required this.alignment,
    required this.width,
    required this.onHorizontalDragStart,
    required this.onHorizontalDragUpdate,
    required this.onHorizontalDragEnd,
  });

  final Key hitRegionKey;
  final Alignment alignment;
  final double width;
  final GestureDragStartCallback onHorizontalDragStart;
  final GestureDragUpdateCallback onHorizontalDragUpdate;
  final GestureDragEndCallback onHorizontalDragEnd;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: SizedBox(
        key: hitRegionKey,
        width: width,
        height: double.infinity,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: onHorizontalDragStart,
          onHorizontalDragUpdate: onHorizontalDragUpdate,
          onHorizontalDragEnd: onHorizontalDragEnd,
        ),
      ),
    );
  }
}

class _PageNavigationButton extends StatelessWidget {
  const _PageNavigationButton({
    required this.alignment,
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final Alignment alignment;
  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: IconButton.filledTonal(
          tooltip: tooltip,
          onPressed: enabled ? onPressed : null,
          icon: Icon(icon),
        ),
      ),
    );
  }
}
