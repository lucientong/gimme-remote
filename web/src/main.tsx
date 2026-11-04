import { render } from 'preact';
import { useEffect, useMemo, useState } from 'preact/hooks';
import { Connection } from './connection';
import { RepeatButton, TouchpadGesture } from './gestures';
import { isStandalone, readStored, store } from './protocol';
import { episodeControls } from './player';
import { PreviewConnection, previewScenes, readPreviewScene, type PreviewScene } from './preview';
import { errorText, getLanguage, getLanguageChoice, languages, setLanguage, t, type LanguageChoice, type TextKey } from './i18n';
import './style.css';

const previewScene = import.meta.env.DEV ? readPreviewScene(location.search) : undefined;
const preview = previewScene ? new PreviewConnection(previewScene) : undefined;
const connection = preview ?? new Connection();
const cancelInputs = () => window.dispatchEvent(new Event('gimme.cancel'));
connection.onDisconnect = cancelInputs;
const version: string = import.meta.env.VITE_APP_VERSION || 'dev';
let rippleId = 0;

function Icon({ name }: { name: string }) {
  const paths: Record<string, preact.ComponentChildren> = {
    // Play state is unknown to the phone, so the button shows both.
    playPause: <><path class="solid" d="M3 5.5 12 12l-9 6.5z" /><path d="M16 6v12M20.5 6v12" /></>,
    back: <><path d="m14 5-9 7 9 7M21 5l-9 7 9 7" /></>,
    next: <><path d="m3 5 9 7-9 7m7-14 9 7-9 7" /></>,
    previousEpisode: <><path d="M5 5v14" /><path class="solid" d="m19 5-11 7 11 7z" /></>,
    nextEpisode: <><path class="solid" d="m5 5 11 7-11 7z" /><path d="M19 5v14" /></>,
    minus: <path d="M5 12h14" />,
    plus: <path d="M5 12h14M12 5v14" />,
    mute: <><path d="M11 5 6 9H3v6h3l5 4zM16 9l5 6m0-6-5 6" /></>,
    fullscreen: <path d="M8 3H3v5m13-5h5v5M3 16v5h5m8 0h5v-5" />,
    switchApp: <><rect x="3" y="3" width="12" height="12" rx="2" /><path d="M9 18v1a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2v-8a2 2 0 0 0-2-2h-1M6 9h6m-2-2 2 2-2 2" /></>,
    left: <path d="m14 5-7 7 7 7" />,
    right: <path d="m10 5 7 7-7 7" />,
    reload: <><path d="M20 10a8 8 0 1 0-1 8M20 4v6h-6" /></>,
    keyboard: <><rect x="2" y="5" width="20" height="14" rx="3" /><path d="M6 9h1m4 0h1m4 0h1M6 13h1m4 0h1m4 0h1M7 16h10" /></>,
    remote: <><rect x="7" y="2" width="10" height="20" rx="5" /><circle cx="12" cy="8" r="2" /><path d="M10 15h4m-4 3h4" /></>,
    lock: <><rect x="5" y="11" width="14" height="10" rx="2" /><path d="M8 11V7a4 4 0 0 1 8 0v4" /></>,
    crosshair: <><circle cx="12" cy="12" r="3" /><path d="M12 2v5m0 10v5M2 12h5m10 0h5" /></>,
  };
  return <svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">{paths[name]}</svg>;
}

function ControlButton({ action, label, short, icon, repeat = false, shortcut = false, className = '', disabled = false }: {
  action: string; label: string; short?: string; icon?: string; repeat?: boolean; shortcut?: boolean; className?: string; disabled?: boolean;
}) {
  const invoke = () => !disabled && connection.send(shortcut ? 'input.keyboard.shortcut' : 'media.command', { action });
  const hold = useMemo(() => new RepeatButton(invoke), [action, shortcut, disabled]);
  useEffect(() => {
    window.addEventListener('gimme.cancel', hold.stop);
    window.addEventListener('blur', hold.stop);
    return () => { hold.stop(); window.removeEventListener('gimme.cancel', hold.stop); window.removeEventListener('blur', hold.stop); };
  }, [hold]);
  return <button class={`control ${className}`} disabled={disabled || !connection.enabled} aria-label={label} title={label}
    onContextMenu={e => e.preventDefault()}
    onPointerDown={e => {
      if (!repeat || !connection.enabled) return;
      e.preventDefault(); e.currentTarget.setPointerCapture(e.pointerId); hold.start();
    }}
    onPointerUp={hold.stop} onPointerCancel={hold.stop} onLostPointerCapture={hold.stop}
    onClick={e => { if (!repeat || e.detail === 0) invoke(); }}>
    {icon ? <Icon name={icon} /> : <span>{label}</span>}
    {icon && className !== 'play' && <small>{short
      ? <><span class="long-label">{label}</span><span class="short-label">{short}</span></> : label}</small>}
  </button>;
}

function Touchpad({ speed, acceleration }: { speed: number; acceleration: boolean }) {
  const gesture = useMemo(() => new TouchpadGesture((type, payload) => connection.send(type, payload)), []);
  const [touching, setTouching] = useState(false);
  const [ripples, setRipples] = useState<{ id: number; x: number; y: number }[]>([]);
  gesture.speed = speed; gesture.acceleration = acceleration;
  useEffect(() => {
    let frame: number;
    const tick = () => { gesture.flush(); frame = requestAnimationFrame(tick); };
    frame = requestAnimationFrame(tick);
    const cancel = () => { gesture.cancel(); setTouching(false); };
    window.addEventListener('gimme.cancel', cancel);
    window.addEventListener('blur', cancel);
    return () => { cancelAnimationFrame(frame); cancel(); window.removeEventListener('gimme.cancel', cancel); window.removeEventListener('blur', cancel); };
  }, [gesture]);
  return <div class={`touchpad ${touching ? 'touching' : ''} ${!connection.enabled ? 'disabled' : ''}`}
    aria-label={t('touchpad')}
    onContextMenu={e => e.preventDefault()}
    onPointerDown={e => {
      if (!connection.enabled) return;
      e.preventDefault(); e.currentTarget.setPointerCapture(e.pointerId);
      gesture.down(e.pointerId, e.clientX, e.clientY); setTouching(true);
      const box = e.currentTarget.getBoundingClientRect();
      const ripple = { id: ++rippleId, x: e.clientX - box.left, y: e.clientY - box.top };
      setRipples(list => [...list.slice(-3), ripple]);
    }}
    onPointerMove={e => { if (connection.enabled) gesture.move(e.pointerId, e.clientX, e.clientY); }}
    onPointerUp={e => { gesture.up(e.pointerId); setTouching(false); }}
    onPointerCancel={() => { gesture.cancel(); setTouching(false); }}>
    <span class="pad-cross"><Icon name="crosshair" /></span>
    {ripples.map(r => <i key={r.id} class="ripple" style={{ left: `${r.x}px`, top: `${r.y}px` }}
      onAnimationEnd={() => setRipples(list => list.filter(item => item.id !== r.id))} />)}
    <div class="pad-hint">{t('padHint')}</div>
  </div>;
}

/** Six visual boxes over one real input, so paste and one-time-code autofill keep working. */
function CodeInput({ value, onChange }: { value: string; onChange: (value: string) => void }) {
  const [focused, setFocused] = useState(false);
  return <div class="code-boxes">
    {Array.from({ length: 6 }, (_, i) => <span class={`code-box ${value[i] ? 'filled' : ''} ${focused && i === Math.min(value.length, 5) ? 'active' : ''}`}>{value[i] ?? ''}</span>)}
    <input id="pair-code" autoComplete="one-time-code" inputMode="numeric" pattern="[0-9]{6}" maxLength={6} required
      value={value} onFocus={() => setFocused(true)} onBlur={() => setFocused(false)}
      onInput={e => onChange(e.currentTarget.value.replace(/\D/g, '').slice(0, 6))} />
  </div>;
}

function App() {
  const [languageChoice, setLanguageChoice] = useState(getLanguageChoice());
  const [systemLanguage, setSystemLanguage] = useState(getLanguage());
  const language = getLanguage();
  useEffect(() => {
    document.documentElement.lang = language === 'zh' ? 'zh-CN' : language;
    document.title = 'Gimme Remote';
  }, [language, systemLanguage]);
  useEffect(() => {
    const changed = () => setSystemLanguage(getLanguage());
    window.addEventListener('languagechange', changed);
    return () => window.removeEventListener('languagechange', changed);
  }, []);
  const [status, setStatus] = useState(connection.state);
  const [code, setCode] = useState(new URLSearchParams(location.hash.slice(1)).get('code') ?? '');
  // A code from the QR link waits for a tap, so the user can still add the page to the Home Screen first.
  const [scanned] = useState(code.length === 6);
  const [pairing, setPairing] = useState(false);
  const [pairError, setPairError] = useState<Error>();
  const [slow, setSlow] = useState(false);
  const [settings, setSettings] = useState(false);
  const [textOpen, setTextOpen] = useState(false);
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const [feedback, setFeedback] = useState<TextKey | Error>();
  const savedSpeed = Number(readStored('gimme.speed', 1.3));
  const [speed, setSpeed] = useState(Number.isFinite(savedSpeed) ? Math.max(0.5, Math.min(3, savedSpeed)) : 1.3);
  const [acceleration, setAcceleration] = useState(readStored('gimme.acceleration', true));
  useEffect(() => {
    connection.onChange = setStatus;
    connection.connect();
    document.addEventListener('visibilitychange', connection.resume);
    window.addEventListener('online', connection.resume);
    const cancel = () => { cancelInputs(); };
    window.addEventListener('pagehide', cancel);
    return () => {
      connection.dispose(); document.removeEventListener('visibilitychange', connection.resume);
      window.removeEventListener('online', connection.resume); window.removeEventListener('pagehide', cancel);
    };
  }, []);
  useEffect(() => { if (!connection.enabled) cancelInputs(); }, [status]);
  useEffect(() => { store('gimme.speed', speed); store('gimme.acceleration', acceleration); }, [speed, acceleration]);
  useEffect(() => {
    setSlow(false);
    if (status.authenticated) return;
    const timer = setTimeout(() => setSlow(true), 10_000);
    return () => clearTimeout(timer);
  }, [status.connected, status.authenticated]);

  const remote = status.remote;
  const episodes = episodeControls(remote);
  const layout = remote?.layout ?? 'generic';
  const blocked = !remote ? ''
    : remote.locked ? t('lockedHint')
    : remote.paused ? t('pausedHint')
    : !remote.accessibility ? t('accessibilityHint') : '';
  const stateText = status.reconnectRequired ? t('disconnected')
    : !status.authenticated ? (connection.paired ? t('connecting') : status.connected ? t('unpaired') : t('offline'))
    : remote?.locked ? t('locked') : remote?.paused ? t('paused') : remote && !remote.accessibility ? t('untrusted') : t('connected');
  async function pair(value = code) {
    if (pairing) return;
    setPairing(true); setPairError(undefined);
    try {
      await connection.request('session.pair', { code: value, deviceName: /iPhone/.test(navigator.userAgent) ? 'iPhone' : 'Phone' });
      setCode('');
    } catch (error) { setPairError(error as Error); }
    finally { setPairing(false); }
  }
  function typeCode(value: string) {
    setCode(value);
    if (value.length === 6 && value !== code && status.connected) void pair(value);
  }
  async function sendText(e: Event) {
    e.preventDefault(); setSending(true); setFeedback(undefined);
    try { await connection.request('input.text.insert', { text }); setText(''); setFeedback(preview ? 'previewText' : 'sent'); }
    catch (error) { setFeedback(error as Error); }
    finally { setSending(false); }
  }
  const waiting = <p class="waiting" role="status"><span class="dots"><i /><i /><i /></span>{t('waiting')}
    {slow && <small>{t('waitingHint')}</small>}</p>;

  const inputButton = <button class={`control ${textOpen ? 'selected' : ''}`} onClick={() => setTextOpen(!textOpen)} disabled={!connection.enabled} aria-label={t('input')}><Icon name="keyboard" /><small>{t('inputShort')}</small></button>;
  const switchButton = <ControlButton action="switchApp" label={t('switchApp')} short={t('switchShort')} icon="switchApp" shortcut />;
  // A player needs no browser navigation; it only keeps text input and app switching.
  const tools = layout === 'iina'
    ? <section class="toolbar two" aria-label={t('textTools')}>
      {inputButton}
      {switchButton}
    </section>
    : <>
      <section class="toolbar five" aria-label={t('browserTools')}>
        <ControlButton action="back" label={t('back')} short={t('backShort')} icon="left" shortcut />
        <ControlButton action="forward" label={t('forward')} short={t('forwardShort')} icon="right" shortcut />
        <ControlButton action="reload" label={t('reload')} icon="reload" shortcut />
        {inputButton}
        {switchButton}
      </section>
      <div class="chips">
        <ControlButton action="address" label={t('address')} shortcut />
        <ControlButton action="previousTab" label={t('previousTab')} shortcut />
        <ControlButton action="nextTab" label={t('nextTab')} shortcut />
        {layout === 'browser' && <ControlButton action="escape" label={t('escape')} shortcut />}
      </div>
      {layout === 'browser' && <p class="volume-note">{t('historyHint')}</p>}
    </>;
  // The browser layout leads with the touchpad, so playback shrinks to one row.
  const player = <section class={`remote-panel ${layout === 'browser' ? 'compact' : ''}`} aria-label={t('player')}>
    {layout === 'browser' && <div class="panel-title">{t('webPlayer')}</div>}
    {episodes && <div class="episode-row" role="group" aria-label={t('episodes')}>
      {typeof episodes.previous === 'boolean'
        ? <ControlButton action="previousEpisode" label={t('previousEpisode')} icon="previousEpisode" disabled={!episodes.previous} /> : <span />}
      <ControlButton action="playPause" label={t('playPause')} icon="playPause" className="play" />
      {typeof episodes.next === 'boolean'
        ? <ControlButton action="nextEpisode" label={t('nextEpisode')} icon="nextEpisode" disabled={!episodes.next} /> : <span />}
    </div>}
    {layout === 'browser'
      ? <div class={`compact-row ${episodes ? 'six' : ''}`}>
        <ControlButton action="seekBackward" label={t('seekBackward')} icon="back" repeat />
        {!episodes && <ControlButton action="playPause" label={t('playPause')} icon="playPause" className="play" />}
        <ControlButton action="seekForward" label={t('seekForward')} icon="next" repeat />
        <ControlButton action="volumeDown" label={t('volumeDown')} icon="minus" repeat />
        <ControlButton action="volumeUp" label={t('volumeUp')} icon="plus" repeat />
        <ControlButton action="mute" label={t('mute')} icon="mute" />
        <ControlButton action="fullscreen" label={t('fullscreen')} icon="fullscreen" />
      </div>
      : <div class="deck">
        <div class="side">
          <ControlButton action="mute" label={t('mute')} icon="mute" />
          <ControlButton action="fullscreen" label={t('fullscreen')} icon="fullscreen" />
          <ControlButton action="escape" label={t('escape')} shortcut />
        </div>
        <div class="transport">
          <ControlButton action="playPause" label={t('playPause')} icon="playPause" className="play" />
          <div class="seek">
            <ControlButton action="seekBackward" label={t('seekBackward')} icon="back" repeat />
            <ControlButton action="seekForward" label={t('seekForward')} icon="next" repeat />
          </div>
        </div>
        <div class="rocker" role="group" aria-label={t('playerVolume')}>
          <ControlButton action="volumeUp" label={t('volumeUp')} icon="plus" repeat />
          <span>{t('volume')}</span>
          <ControlButton action="volumeDown" label={t('volumeDown')} icon="minus" repeat />
        </div>
      </div>}
    <p class="volume-note">{t('volumeHint')}</p>
  </section>;
  const touchpad = <Touchpad speed={speed} acceleration={acceleration} />;

  return <main class={`shell ${layout}`}>
    <header class="header">
      <div class="brand"><Icon name="remote" /><span>gimme<span class="brand-dot">.</span></span></div>
      <button class={`target ${connection.enabled ? 'online' : ''}`} onClick={() => setSettings(!settings)} aria-label={t('target')}>
        <i /><span>{status.authenticated ? remote?.appName ?? 'Mac' : 'Mac'} · {preview ? t('preview') : stateText}</span><span class="chevron">⌄</span>
      </button>
    </header>
    {import.meta.env.DEV && (preview ? <section class="preview-panel" aria-label={t('previewTitle')}>
      <div class="section-top"><strong>{t('previewTitle')}</strong><a href={location.pathname}>{t('previewBack')}</a></div>
      <label for="preview-scene">{t('previewScene')}</label>
      <select id="preview-scene" value={preview.scene} onChange={e => {
        const scene = e.currentTarget.value as PreviewScene;
        preview.setScene(scene); setFeedback(undefined);
        const url = new URL(location.href);
        url.searchParams.set('preview', preview.scene);
        history.replaceState(null, '', url.pathname + url.search + url.hash);
      }}>
        {Object.entries(previewScenes).map(([value, label]) => <option value={value}>{t(label)}</option>)}
      </select>
      <p role="status">{preview.lastAction || t('previewHint')}</p>
    </section> : <a class="preview-entry" href={`${location.pathname}?preview=browser`}>{t('previewEntry')}</a>)}
    {status.error && errorText(status.error) !== pairError?.message && !blocked && <div class="notice" role="status">{errorText(status.error)}</div>}
    {settings && <section class="settings">
      <div class="section-top"><span class="section-label">{t('settings')}</span><button class="text-button" onClick={() => setSettings(false)}>{t('done')}</button></div>
      <label for="language">{t('language')}</label>
      <select id="language" value={languageChoice} onChange={e => {
        const value = e.currentTarget.value as LanguageChoice;
        setLanguage(value); setLanguageChoice(value);
      }}>
        <option value="auto">{t('auto')}</option>
        {Object.entries(languages).map(([value, label]) => <option value={value}>{label}</option>)}
      </select>
      <label for="speed">{t('speed')} <strong>{speed.toFixed(1)}×</strong></label>
      <input id="speed" type="range" min="0.5" max="3" step="0.1" value={speed} onInput={e => setSpeed(Number(e.currentTarget.value))} />
      <label class="checkbox"><input type="checkbox" checked={acceleration} onChange={e => setAcceleration(e.currentTarget.checked)} />{t('acceleration')}</label>
      <p>{t('homeScreen')}</p>
    </section>}
    {status.authenticated ? <div class="deck-area">
      {layout === 'browser' ? <>{touchpad}{tools}{player}</> : <>{player}{touchpad}{tools}</>}
      {textOpen && <form class="text-panel" onSubmit={sendText}>
        <label for="remote-text">{t('textLabel')}</label>
        <textarea id="remote-text" rows={3} value={text} onInput={e => setText(e.currentTarget.value)} placeholder={t('textPlaceholder')} />
        <div class="text-actions"><ControlButton action="enter" label={t('enter')} shortcut />
          <button class="primary" disabled={!connection.enabled || !text || sending || new TextEncoder().encode(text).length > 8192}>{sending ? t('sending') : t('sendText')}</button></div>
        <span role="status" class="feedback">{feedback instanceof Error ? feedback.message : feedback ? t(feedback) : ''}</span>
      </form>}
      {blocked && <div class="blocked" role="status"><div><Icon name="lock" /><span>{blocked}</span></div></div>}
    </div>
    : status.reconnectRequired ? <section class="pair-panel connecting">
      <p role="status">{t('disconnectedHint')}</p>
      <button class="primary" onClick={() => connection.reconnectNow()}>{t('reconnect')}</button>
    </section>
    : connection.paired ? <section class="pair-panel connecting">{waiting}</section>
    : <section class="pair-panel">
      <h1>{t('pairTitle')}</h1>
      <p>{t('wifiHint')}</p>
      <p>{isStandalone() && !code ? t('standalonePair')
        : scanned && code.length === 6 ? t('scannedPair') : t('manualPair')}</p>
      <form onSubmit={e => { e.preventDefault(); void pair(); }}>
        <label for="pair-code">{t('pairCode')}</label>
        <CodeInput value={code} onChange={typeCode} />
        <button class="primary wide" disabled={!status.connected || code.length !== 6 || pairing}>{pairing ? t('pairing') : t('pair')}</button>
        {pairError && <p role="alert" class="error">{pairError.message}</p>}
      </form>
      {!status.connected && waiting}
      {!isStandalone() && <small>{t('addHome')}</small>}
      <small>{t('inputOnly')}</small>
    </section>}
    <footer>Gimme Remote {version === 'dev' ? version : `v${version}`}</footer>
  </main>;
}

render(<App />, document.getElementById('app')!);
