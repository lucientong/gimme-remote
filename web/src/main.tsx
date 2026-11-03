import { render } from 'preact';
import { useEffect, useMemo, useState } from 'preact/hooks';
import { Connection } from './connection';
import { RepeatButton, TouchpadGesture } from './gestures';
import { isStandalone, readStored, store } from './protocol';
import './style.css';

const connection = new Connection();
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

function ControlButton({ action, label, short, icon, repeat = false, shortcut = false, className = '' }: {
  action: string; label: string; short?: string; icon?: string; repeat?: boolean; shortcut?: boolean; className?: string;
}) {
  const invoke = () => connection.send(shortcut ? 'input.keyboard.shortcut' : 'media.command', { action });
  const hold = useMemo(() => new RepeatButton(invoke), [action, shortcut]);
  useEffect(() => {
    window.addEventListener('gimme.cancel', hold.stop);
    window.addEventListener('blur', hold.stop);
    return () => { hold.stop(); window.removeEventListener('gimme.cancel', hold.stop); window.removeEventListener('blur', hold.stop); };
  }, [hold]);
  return <button class={`control ${className}`} disabled={!connection.enabled} aria-label={label} title={label}
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
    aria-label="触控板：单指移动，轻点单击，双指滚动或轻点右键，按住后拖动"
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
    <div class="pad-hint">轻点点击 · 双指滚动 · 按住拖动</div>
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
  const [status, setStatus] = useState(connection.state);
  const [code, setCode] = useState(new URLSearchParams(location.hash.slice(1)).get('code') ?? '');
  // A code from the QR link waits for a tap, so the user can still add the page to the Home Screen first.
  const [scanned] = useState(code.length === 6);
  const [pairing, setPairing] = useState(false);
  const [pairError, setPairError] = useState('');
  const [slow, setSlow] = useState(false);
  const [settings, setSettings] = useState(false);
  const [textOpen, setTextOpen] = useState(false);
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const [feedback, setFeedback] = useState('');
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
  const layout = remote?.layout ?? 'generic';
  const blocked = !remote ? ''
    : remote.locked ? 'Mac 已锁定，请在 Mac 上解锁'
    : remote.paused ? '遥控已暂停，请在 Mac 菜单栏恢复'
    : !remote.accessibility ? '请先在 Mac 菜单栏授权辅助功能' : '';
  const stateText = !status.authenticated ? (connection.paired ? '连接中' : status.connected ? '未配对' : '未连接')
    : remote?.locked ? '已锁定' : remote?.paused ? '已暂停' : remote && !remote.accessibility ? '未授权' : '已连接';
  async function pair(value = code) {
    if (pairing) return;
    setPairing(true); setPairError('');
    try {
      await connection.request('session.pair', { code: value, deviceName: /iPhone/.test(navigator.userAgent) ? 'iPhone' : 'Phone' });
      setCode('');
    } catch (error) { setPairError((error as Error).message); }
    finally { setPairing(false); }
  }
  function typeCode(value: string) {
    setCode(value);
    if (value.length === 6 && value !== code && status.connected) void pair(value);
  }
  async function sendText(e: Event) {
    e.preventDefault(); setSending(true); setFeedback('');
    try { await connection.request('input.text.insert', { text }); setText(''); setFeedback('已发送输入'); }
    catch (error) { setFeedback((error as Error).message); }
    finally { setSending(false); }
  }
  const waiting = <p class="waiting" role="status"><span class="dots"><i /><i /><i /></span>正在连接 Mac…
    {slow && <small>请确认 Mac 上的 Gimme Remote 已打开，且手机和 Mac 在同一个 Wi-Fi 下。</small>}</p>;

  const inputButton = <button class={`control ${textOpen ? 'selected' : ''}`} onClick={() => setTextOpen(!textOpen)} disabled={!connection.enabled} aria-label="输入文本"><Icon name="keyboard" /><small>输入</small></button>;
  const switchButton = <ControlButton action="switchApp" label="切换应用" short="切换" icon="switchApp" shortcut />;
  // A player needs no browser navigation; it only keeps text input and app switching.
  const tools = layout === 'iina'
    ? <section class="toolbar two" aria-label="文本与切换工具">
      {inputButton}
      {switchButton}
    </section>
    : <>
      <section class="toolbar five" aria-label="浏览器与文本工具">
        <ControlButton action="back" label="后退" icon="left" shortcut />
        <ControlButton action="forward" label="前进" icon="right" shortcut />
        <ControlButton action="reload" label="刷新" icon="reload" shortcut />
        {inputButton}
        {switchButton}
      </section>
      <div class="chips">
        <ControlButton action="address" label="地址栏" shortcut />
        <ControlButton action="previousTab" label="上一标签" shortcut />
        <ControlButton action="nextTab" label="下一标签" shortcut />
        {layout === 'browser' && <ControlButton action="escape" label="Esc" shortcut />}
      </div>
    </>;
  // The browser layout leads with the touchpad, so playback shrinks to one row.
  const player = <section class={`remote-panel ${layout === 'browser' ? 'compact' : ''}`} aria-label="播放器遥控">
    {layout === 'browser' && <div class="panel-title">网页播放器</div>}
    {layout === 'browser'
      ? <div class="compact-row">
        <ControlButton action="seekBackward" label="快退" icon="back" repeat />
        <ControlButton action="playPause" label="播放 / 暂停" icon="playPause" className="play" />
        <ControlButton action="seekForward" label="快进" icon="next" repeat />
        <ControlButton action="volumeDown" label="音量 −" icon="minus" repeat />
        <ControlButton action="volumeUp" label="音量 +" icon="plus" repeat />
        <ControlButton action="mute" label="静音" icon="mute" />
        <ControlButton action="fullscreen" label="全屏" icon="fullscreen" />
      </div>
      : <div class="deck">
        <div class="side">
          <ControlButton action="mute" label="静音" icon="mute" />
          <ControlButton action="fullscreen" label="全屏" icon="fullscreen" />
          <ControlButton action="escape" label="Esc" shortcut />
        </div>
        <div class="transport">
          <ControlButton action="playPause" label="播放 / 暂停" icon="playPause" className="play" />
          <div class="seek">
            <ControlButton action="seekBackward" label="快退" icon="back" repeat />
            <ControlButton action="seekForward" label="快进" icon="next" repeat />
          </div>
        </div>
        <div class="rocker" role="group" aria-label="播放器音量">
          <ControlButton action="volumeUp" label="音量 +" icon="plus" repeat />
          <span>音量</span>
          <ControlButton action="volumeDown" label="音量 −" icon="minus" repeat />
        </div>
      </div>}
    <p class="volume-note">调节播放器音量 · 电视总音量用电视遥控器</p>
  </section>;
  const touchpad = <Touchpad speed={speed} acceleration={acceleration} />;

  return <main class={`shell ${layout}`}>
    <header class="header">
      <div class="brand"><Icon name="remote" /><span>gimme<span class="brand-dot">.</span></span></div>
      <button class={`target ${connection.enabled ? 'online' : ''}`} onClick={() => setSettings(!settings)} aria-label="连接状态和触控板设置">
        <i /><span>{status.authenticated ? remote?.appName ?? 'Mac' : 'Mac'} · {stateText}</span><span class="chevron">⌄</span>
      </button>
    </header>
    {status.error && status.error !== pairError && !blocked && <div class="notice" role="status">{status.error}</div>}
    {settings && <section class="settings">
      <div class="section-top"><span class="section-label">手感设置</span><button class="text-button" onClick={() => setSettings(false)}>完成</button></div>
      <label for="speed">指针速度 <strong>{speed.toFixed(1)}×</strong></label>
      <input id="speed" type="range" min="0.5" max="3" step="0.1" value={speed} onInput={e => setSpeed(Number(e.currentTarget.value))} />
      <label class="checkbox"><input type="checkbox" checked={acceleration} onChange={e => setAcceleration(e.currentTarget.checked)} />指针加速</label>
      <p>Safari → 分享 → 添加到主屏幕，下次一键打开。主屏幕入口与 Safari 分开保存配对，首次打开需在 Mac 上更新配对码后再输入一次。</p>
    </section>}
    {status.authenticated ? <div class="deck-area">
      {layout === 'browser' ? <>{touchpad}{tools}{player}</> : <>{player}{touchpad}{tools}</>}
      {textOpen && <form class="text-panel" onSubmit={sendText}>
        <label for="remote-text">输入到 Mac 当前焦点</label>
        <textarea id="remote-text" rows={3} value={text} onInput={e => setText(e.currentTarget.value)} placeholder="中文搜索词、网址或任何文字…" />
        <div class="text-actions"><ControlButton action="enter" label="回车" shortcut />
          <button class="primary" disabled={!connection.enabled || !text || sending || new TextEncoder().encode(text).length > 8192}>{sending ? '发送中…' : '发送整段文字'}</button></div>
        <span role="status" class="feedback">{feedback}</span>
      </form>}
      {blocked && <div class="blocked" role="status"><div><Icon name="lock" /><span>{blocked}</span></div></div>}
    </div>
    : connection.paired ? <section class="pair-panel connecting">{waiting}</section>
    : <section class="pair-panel">
      <h1>连接你的 Mac</h1>
      <p>确认手机和 Mac 在同一个 Wi-Fi 下。</p>
      <p>{isStandalone() && !code ? '主屏幕入口需要单独配对一次：在 Mac 菜单栏的 Gimme Remote 点“更新配对码”，再输入新的 6 位码。'
        : scanned && code.length === 6 ? '配对码已从二维码填好，点“连接 Mac”即可。'
        : '在 Mac 菜单栏打开 Gimme Remote，输入面板上的 6 位配对码。'}</p>
      <form onSubmit={e => { e.preventDefault(); void pair(); }}>
        <label for="pair-code">配对码</label>
        <CodeInput value={code} onChange={typeCode} />
        <button class="primary wide" disabled={!status.connected || code.length !== 6 || pairing}>{pairing ? '配对中…' : '连接 Mac'}</button>
        {pairError && <p role="alert" class="error">{pairError}</p>}
      </form>
      {!status.connected && waiting}
      {!isStandalone() && <small>想放到主屏幕：先“分享 → 添加到主屏幕”，再从主屏幕图标打开并配对。</small>}
      <small>只传输按键操作，不会传输屏幕画面。</small>
    </section>}
    <footer>Gimme Remote {version === 'dev' ? version : `v${version}`}</footer>
  </main>;
}

render(<App />, document.getElementById('app')!);
