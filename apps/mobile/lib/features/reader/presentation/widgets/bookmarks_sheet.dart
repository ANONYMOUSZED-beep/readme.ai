import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/state_message.dart';
import '../../application/reader_controller.dart';
import '../../application/reader_providers.dart';
import '../../domain/bookmark.dart';

/// Bottom sheet listing the book's saved positions.
///
/// When [bookText] is provided, each bookmark previews the passage it points
/// to and its position in the book.
class BookmarksSheet extends ConsumerWidget {
  const BookmarksSheet({
    required this.bookId,
    required this.onJump,
    this.bookText,
    super.key,
  });

  final String bookId;
  final void Function(Bookmark) onJump;
  final String? bookText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(bookmarksProvider(bookId));
    final theme = Theme.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Bookmarks',
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close bookmarks',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: bookmarks.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => const StateMessage(
                    icon: Icons.cloud_off_rounded,
                    title: "Couldn't load bookmarks.",
                    message: 'Close this sheet and try again.',
                  ),
                  data: (items) => items.isEmpty
                      ? const StateMessage(
                          icon: Icons.bookmark_add_outlined,
                          title: 'No bookmarks yet',
                          message:
                              'Tap the bookmark icon while reading to save '
                              'your place.',
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.only(right: 8),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) => _BookmarkTile(
                            bookmark: items[index],
                            bookText: bookText,
                            onTap: () => onJump(items[index]),
                            onDelete: () => ref
                                .read(readerControllerProvider)
                                .deleteBookmark(bookId, items[index].id),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookmarkTile extends StatelessWidget {
  const _BookmarkTile({
    required this.bookmark,
    required this.bookText,
    required this.onTap,
    required this.onDelete,
  });

  final Bookmark bookmark;
  final String? bookText;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = bookText;
    final offset = int.tryParse(bookmark.anchor) ?? 0;
    final excerpt = text == null ? null : _excerpt(text, offset);
    final position = text == null || text.isEmpty
        ? null
        : '${(offset / text.length * 100).clamp(0, 100).round()}%';
    final meta = [?position, _date(bookmark.createdAt)].join(' · ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.bookmark_rounded,
                size: 20,
                color: theme.colorScheme.secondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bookmark.label ?? 'Bookmark',
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (excerpt != null && excerpt.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      excerpt,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.serif,
                        fontStyle: FontStyle.italic,
                        fontSize: 15,
                        height: 1.45,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(meta, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Delete bookmark',
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              color: theme.colorScheme.onSurfaceVariant,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// A short, whitespace-normalised preview of [text] starting near [offset].
String _excerpt(String text, int offset) {
  final start = offset.clamp(0, text.length);
  final end = (start + 160).clamp(0, text.length);
  final snippet = text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ');
  return end < text.length ? '${snippet.trim()}…' : snippet.trim();
}

String _date(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = date.toLocal();
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}
