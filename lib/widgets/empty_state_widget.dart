import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A reusable empty-state view for lists and search results.
///
/// Used wherever a collection can be empty — orders, jobs, chats,
/// notifications, inventory — and especially for search with no matches
/// ([forSearch] mode names the query in the message).
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;

  /// Short heading, e.g. 'No orders yet'.
  final String title;

  /// One-line explanation or suggestion.
  final String? subtitle;

  /// When set, renders search-specific copy: `No results for "query"`.
  final String? searchQuery;

  final VoidCallback? onAction;

  final String? actionLabel;

  const EmptyStateWidget({
    super.key,
    this.icon = Icons.inbox_outlined,
    this.title = 'Nothing here yet',
    this.subtitle,
    this.searchQuery,
    this.onAction,
    this.actionLabel,
  });

  /// Convenience for search screens.
  const EmptyStateWidget.search({
    super.key,
    required String query,
    String what = 'results',
  })  : icon = Icons.search_off,
        title = 'No $what found',
        subtitle = 'We could not find anything matching your search. Try different keywords.',
        searchQuery = query,
        onAction = null,
        actionLabel = null;

  @override
  Widget build(BuildContext context) {
    final bool isSearch = searchQuery != null && searchQuery!.isNotEmpty;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSearch ? Icons.search_off : icon,
              size: 64,
              color: AppTheme.borderGray,
            ),
            const SizedBox(height: 16),
            Text(
              isSearch ? 'No results for "$searchQuery"' : title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            if (subtitle != null || isSearch) ...[
              const SizedBox(height: 8),
              Text(
                isSearch
                    ? (subtitle ??
                        'We could not find anything matching your search. Try different keywords.')
                    : subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppTheme.textLight),
              ),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
