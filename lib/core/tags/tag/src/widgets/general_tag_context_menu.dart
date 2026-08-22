// Package imports:
import 'package:context_menus/context_menus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:i18n/i18n.dart';
import 'package:flutter/material.dart';

// Project imports:
import '../../../../../foundation/clipboard.dart';
import '../../../../blacklists/providers.dart';
import '../../../../posts/details/src/routes/details_route_context.dart';
import '../../../../posts/details/src/widgets/post_details_page.dart';
import '../../../../search/search/routes.dart';
import '../../../../search/selected_tags/types.dart';
import '../../../favorites/providers.dart';

class GeneralTagContextMenu extends ConsumerWidget
    with TagContextMenuButtonConfigMixin {
  const GeneralTagContextMenu({
    required this.tag,
    required this.child,
    super.key,
    this.itemBindings = const {},
  });

  final String tag;
  final Widget child;
  final Map<String, void Function()> itemBindings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final globalNotifier = ref.watch(globalBlacklistedTagsProvider.notifier);

    return ContextMenuRegion(
      contextMenu: GenericContextMenu(
        buttonConfigs: [
          copyButton(context, tag),
          searchButton(ref, tag),
          addToSearchButton(context, ref, tag),
          excludeFromSearchButton(context, ref, tag),
          ContextMenuButtonConfig(
            context.t.post.detail.add_to_favorites,
            onPressed: () {
              ref.read(favoriteTagsProvider.notifier).add(tag);
            },
          ),
          ContextMenuButtonConfig(
            context.t.tags.actions.add_to_blacklist_global,
            onPressed: () {
              globalNotifier.addTagWithToast(context, tag);
            },
          ),
          for (final entry in itemBindings.entries)
            ContextMenuButtonConfig(
              entry.key,
              onPressed: entry.value,
            ),
        ],
      ),
      child: child,
    );
  }
}

mixin TagContextMenuButtonConfigMixin {
  ContextMenuButtonConfig copyButton(BuildContext context, String tag) =>
      ContextMenuButtonConfig(
        context.t.tags.actions.copy_single,
        onPressed: () {
          AppClipboard.copyAndToast(
            context,
            tag,
            message: context.t.generic.copied,
          );
        },
      );

  ContextMenuButtonConfig searchButton(WidgetRef ref, String tag) =>
      ContextMenuButtonConfig(
        ref.context.t.tags.actions.search_single,
        onPressed: () {
          goToSearchPage(ref, tag: tag);
        },
      );

  SearchTagSet _getCurrentTags(BuildContext context, WidgetRef ref) {
    try {
      final state = GoRouterState.of(ref.context);
      if (state.extra is DetailsRouteContext) {
        final detailsContext = state.extra as DetailsRouteContext;
        if (detailsContext.searchTags != null) {
          return detailsContext.searchTags!.clone();
        }
      }
    } catch (_) {}

    final lastParams = ref.read(lastSearchParamsProvider);
    final currentTags = lastParams?.tags?.clone() ?? SearchTagSet();
    if (lastParams?.query != null && lastParams!.query!.isNotEmpty) {
      currentTags.merge(SearchTagSet.fromString(lastParams.query));
    }
    return currentTags;
  }

  ContextMenuButtonConfig addToSearchButton(BuildContext context, WidgetRef ref, String tag) =>
      ContextMenuButtonConfig(
        context.t.tags.actions.add_to_search,
        onPressed: () {
          final currentTags = _getCurrentTags(context, ref);
          currentTags.addTag(TagSearchItem.raw(tag: tag));
          goToSearchPage(ref, tags: currentTags);
        },
      );

  ContextMenuButtonConfig excludeFromSearchButton(BuildContext context, WidgetRef ref, String tag) =>
      ContextMenuButtonConfig(
        context.t.tags.actions.exclude_from_search,
        onPressed: () {
          final currentTags = _getCurrentTags(context, ref);
          currentTags.addTag(TagSearchItem.fromString('-$tag'));
          goToSearchPage(ref, tags: currentTags);
        },
      );
}
