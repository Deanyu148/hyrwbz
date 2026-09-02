class SearchTerm {
  final String value;
  final bool excluded;

  const SearchTerm(this.value, {this.excluded = false});
}

List<SearchTerm> parseSearchQuery(String query) {
  final terms = <SearchTerm>[];
  final pattern = RegExp(r'''(-?)(?:"([^"]+)"|'([^']+)'|(\S+))''');
  for (final match in pattern.allMatches(query.trim())) {
    final raw = match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
    final value = raw.trim().toLowerCase();
    if (value.isEmpty || value == '-') continue;
    final embeddedExclude = value.startsWith('-') && match.group(1)!.isEmpty;
    final normalized = embeddedExclude ? value.substring(1) : value;
    if (normalized.isEmpty) continue;
    terms.add(SearchTerm(
      normalized,
      excluded: match.group(1) == '-' || embeddedExclude,
    ));
  }
  return terms;
}

/// 类似常见搜索引擎的基础匹配规则：
/// - 空格分隔的多个关键词必须全部命中；
/// - 引号包裹的内容作为完整短语；
/// - `-关键词` 表示排除；
/// - 英文字母不区分大小写。
bool matchesSearchQuery(String query, Iterable<Object?> values) {
  final terms = parseSearchQuery(query);
  if (terms.isEmpty) return true;
  final haystack = values
      .where((value) => value != null)
      .map((value) => value.toString().toLowerCase())
      .join('\n');
  for (final term in terms) {
    final contains = haystack.contains(term.value);
    if (term.excluded ? contains : !contains) return false;
  }
  return true;
}
