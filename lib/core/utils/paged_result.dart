/// A page of a list: items plus what is needed to ask for the next one.
class PagedResult<T> {
  const PagedResult({
    required this.items,
    required this.hasMore,
    required this.total,
  });

  final List<T> items;
  final bool hasMore;
  final int total;
}
