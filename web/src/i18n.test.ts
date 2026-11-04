import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { catalogs, getLanguage, languages, LocalizedError, readLanguageChoice, resolveLanguage, setLanguage, t, type Language, type TextKey } from './i18n';

let storage: Map<string, string>;
beforeEach(() => {
  storage = new Map();
  vi.stubGlobal('localStorage', {
    getItem: (key: string) => storage.get(key) ?? null,
    setItem: (key: string, value: string) => storage.set(key, value),
  });
});
afterEach(() => { vi.unstubAllGlobals(); setLanguage('auto'); });

it('resolves region and script tags, walks preferred languages, and falls back to English', () => {
  expect(resolveLanguage(['zh-Hant-TW'])).toBe('zh');
  expect(resolveLanguage(['EN_us'])).toBe('en');
  expect(resolveLanguage(['fr-FR', 'ja-JP', 'en'])).toBe('ja');
  expect(resolveLanguage(['ko-KR'])).toBe('ko');
  expect(resolveLanguage(['de-DE'])).toBe('en');
  expect(resolveLanguage([])).toBe('en');
});

it('has complete catalogs with matching placeholders', () => {
  const placeholders = (text: string) => [...text.matchAll(/\{(\w+)\}/g)].map(match => match[1]).sort();
  const keys = Object.keys(catalogs.en) as TextKey[];
  for (const language of Object.keys(languages) as Language[]) {
    expect(Object.keys(catalogs[language]).sort()).toEqual([...keys].sort());
    for (const key of keys) {
      expect(catalogs[language][key].trim(), `${language}.${key}`).not.toBe('');
      expect(placeholders(catalogs[language][key]), `${language}.${key}`).toEqual(placeholders(catalogs.en[key]));
    }
  }
});

it('persists manual selection and restores automatic language detection', () => {
  vi.stubGlobal('navigator', { languages: ['ko-KR'], language: 'ko-KR' });
  setLanguage('auto');
  expect(getLanguage()).toBe('ko');
  setLanguage('ja');
  expect(readLanguageChoice()).toBe('ja');
  expect(getLanguage()).toBe('ja');
  vi.stubGlobal('navigator', { languages: ['en-US'], language: 'en-US' });
  expect(getLanguage()).toBe('ja');
  setLanguage('auto');
  expect(getLanguage()).toBe('en');
  expect(readLanguageChoice()).toBe('auto');
});

it('handles invalid preferences and unavailable storage', () => {
  storage.set('gimme.language', '"fr"');
  expect(readLanguageChoice()).toBe('auto');
  storage.set('gimme.language', 'invalid json');
  expect(readLanguageChoice()).toBe('auto');
  vi.stubGlobal('localStorage', { getItem: () => { throw new Error(); }, setItem: () => { throw new Error(); } });
  setLanguage('en');
  expect(getLanguage()).toBe('en');
  expect(readLanguageChoice()).toBe('auto');
});

it('formats action names as plain text and translates retained error objects', () => {
  expect(t('previewAction', { action: '<script>' }, 'en')).toContain('“<script>”');
  setLanguage('zh');
  const error = new LocalizedError('invalidPairingCode');
  expect(error.message).toBe(catalogs.zh.invalidPairingCode);
  setLanguage('en');
  expect(error.message).toBe(catalogs.en.invalidPairingCode);
  expect(new LocalizedError('unknown').message).toBe(catalogs.en.operationFailed);
});
