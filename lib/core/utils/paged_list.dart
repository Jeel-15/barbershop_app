import 'package:barbershop_app/core/utils/paged_result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Rows loaded so far plus what is needed to ask for the next page.
class PagedState<T> {
  const PagedState({
    required this.items,
    required this.hasMore,
    required this.total,
    this.page = 1,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  final List<T> items;
  final bool hasMore;
  final int total;
  final int page;
  final bool loadingMore;
  final bool loadMoreFailed;

  PagedState<T> copyWith({
    List<T>? items,
    bool? hasMore,
    int? page,
    bool? loadingMore,
    bool? loadMoreFailed,
  }) => PagedState(
    items: items ?? this.items,
    hasMore: hasMore ?? this.hasMore,
    total: total,
    page: page ?? this.page,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
  );
}

/// A list that loads page by page. A subclass only says how to fetch a page.
abstract class PagedNotifier<T> extends AsyncNotifier<PagedState<T>> {
  Future<PagedResult<T>> fetch(int page);

  @override
  Future<PagedState<T>> build() async {
    final first = await fetch(1);
    return PagedState(
      items: first.items,
      hasMore: first.hasMore,
      total: first.total,
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> loadMore() async {
    final s = state.value;
    if (s == null || !s.hasMore || s.loadingMore) return;
    state = AsyncData(s.copyWith(loadingMore: true, loadMoreFailed: false));
    try {
      final next = await fetch(s.page + 1);
      state = AsyncData(
        s.copyWith(
          items: [...s.items, ...next.items],
          hasMore: next.hasMore,
          page: s.page + 1,
          loadingMore: false,
        ),
      );
    } catch (_) {
      // Keep what is shown; the footer offers a retry.
      state = AsyncData(s.copyWith(loadingMore: false, loadMoreFailed: true));
    }
  }
}
