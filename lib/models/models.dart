enum MediaKind { video, image }

enum TaxonomyKind { style, teacher, studio }

extension TaxonomyKindX on TaxonomyKind {
  String get dbValue => name;
  static TaxonomyKind fromDb(String v) => TaxonomyKind.values
      .firstWhere((k) => k.name == v, orElse: () => TaxonomyKind.style);
}
