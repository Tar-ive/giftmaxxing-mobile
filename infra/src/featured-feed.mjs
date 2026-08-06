// Place editorially featured posts first without duplicating them later in the
// ranked page. The caller controls when this applies (page one only).
export function prependFeatured(items, featured, limit) {
  const pinnedIds = new Set(featured.map((item) => item.postId));
  return [
    ...featured.map((item) => ({ ...item, featured: true })),
    ...items.filter((item) => !pinnedIds.has(item.postId)),
  ].slice(0, limit);
}
