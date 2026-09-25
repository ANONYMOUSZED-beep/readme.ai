import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/chapter_mark.dart';

/// Bottom sheet listing a book's chapters; the current one is highlighted.
class ContentsSheet extends StatelessWidget {
  const ContentsSheet({
    required this.chapters,
    required this.currentOffset,
    required this.onSelect,
    super.key,
  });

  final List<ChapterMark> chapters;

  /// The reader's current character offset, used to mark "you are here".
  final int currentOffset;
  final ValueChanged<ChapterMark> onSelect;

  /// Index of the chapter containing [currentOffset].
  int get _currentIndex {
    var index = 0;
    for (var i = 0; i < chapters.length; i++) {
      if (chapters[i].startOffset <= currentOffset) {
        index = i;
      }
    }
    return index;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final current = _currentIndex;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
              child: Text(l10n.contents, style: theme.textTheme.titleLarge),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: chapters.length,
                itemBuilder: (context, index) {
                  final chapter = chapters[index];
                  final selected = index == current;
                  return ListTile(
                    selected: selected,
                    selectedTileColor: theme.colorScheme.primaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    leading: Text(
                      '${index + 1}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    title: Text(
                      chapter.title ?? l10n.chapterNumber(index + 1),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => onSelect(chapter),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
