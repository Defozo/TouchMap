import { resourceManager } from '@kit.LocalizationKit';
import { setTranslationResolver } from '../domain/i18n';

export { tr } from '../domain/i18n';

/** Resolve strings by the system locale, with the bundled base English catalog as fallback. */
export function initializeI18n(manager: resourceManager.ResourceManager): void {
  const resolved = new Map<string, string>();
  setTranslationResolver((key: string): string => {
    const cached = resolved.get(key);
    if (cached !== undefined) { return cached; }
    const value = manager.getStringByNameSync(key);
    resolved.set(key, value);
    return value;
  });
}
