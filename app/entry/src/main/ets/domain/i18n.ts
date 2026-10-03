import { englishText } from './EnglishStrings';

let resourceLookup: ((key: string) => string) | undefined;

/** Native code supplies its locale-aware resource manager; pure domain callers retain English. */
export function setTranslationResolver(resolver: (key: string) => string): void {
  resourceLookup = resolver;
}

/** Named resource templates use numbered placeholders; values are never reinterpreted as templates. */
export function tr(key: string, values: string[] = []): string {
  let template = '';
  if (resourceLookup) {
    try { template = resourceLookup(key); } catch (_) { /* A missing resource falls back to its English catalog. */ }
  }
  if (!template) template = englishText(key);
  return template.replace(/\{(\d+)\}/g, (match: string, index: string): string => {
    const value = values[Number(index)];
    return value === undefined ? match : value;
  });
}
