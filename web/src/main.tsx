import { render } from 'preact';
import { useEffect, useMemo, useState } from 'preact/hooks';
import { Connection } from './connection';
import { RepeatButton, TouchpadGesture } from './gestures';
import { readStored, store } from './protocol';
import './style.css';

const connection = new Connection();
const cancelInputs = () => window.dispatchEvent(new Event('gimme.cancel'));
connection.onDisconnect = cancelInputs;

function Icon({ name }: { name: string }) {
  const paths: Record<string, preact.ComponentChildren> = {
    play: <path d="m9 5 11 7-11 7z" />,
    back: <><path d="m14 5-9 7 9 7M21 5l-9 7 9 7" /></>,
    next: <><path d="m3 5 9 7-9 7m7-14 9 7-9 7" /></>,
    minus: <path d="M5 12h14" />,
    plus: <path d="M5 12h14M12 5v14" />,
    mute: <><path d="M11 5 6 9H3v6h3l5 4zM16 9l5 6m0-6-5 6" /></>,
    fullscreen: <path d="M8 3H3v5m13-5h5v5M3 16v5h5m8 0h5v-5" />,
    left: <path d="m14 5-7 7 7 7" />,
    right: <path d="m10 5 7 7-7 7" />,
    reload: <><path d="M20 10a8 8 0 1 0-1 8M20 4v6h-6" /></>,
    keyboard: <><rect x="2" y="5" width="20" height="14" rx="3" /><path d="M6 9h1m4 0h1m4 0h1M6 13h1m4 0h1m4 0h1M7 16h10" /></>,
    remote: <><rect x="7" y="2" width="10" height="20" rx="5" /><circle cx="12" cy="8" r="2" /><path d="M10 15h4m-4 3h4" /></>,
  };
  return <svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">{paths[name]}</svg>;
}

function ControlButton({ action, label, icon, repeat = false, shortcut = false, className = '' }: {
  action: string; label: string; icon?: string; repeat?: boolean; shortcut?: boolean; className?: string;
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
    {icon && className !== 'play' && <small>{label}</small>}
  </button>;
}

function Touchpad({ speed, acceleration }: { speed: number; acceleration: boolean }) {
  const gesture = useMemo(() => new TouchpadGesture((type, payload) => connection.send(type, payload)), []);
  const [touching, setTouching] = useState(false);
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
    }}
    onPointerMove={e => { if (connection.enabled) gesture.move(e.pointerId, e.clientX, e.clientY); }}
    onPointerUp={e => { gesture.up(e.pointerId); setTouching(false); }}
    onPointerCancel={() => { gesture.cancel(); setTouching(false); }}>
    <span class="pad-cross">+</span>
    <div class="pad-label"><span>TOUCHPAD</span><small>看电视上的指针</small></div>
    <div class="pad-hint">轻点点击 · 双指滚动 · 按住拖动</div>
  </div>;
}

function App() {
  const [status, setStatus] = useState(connection.state);
  const [code, setCode] = useState(new URLSearchParams(location.hash.slice(1)).get('code') ?? '');
  const [pairing, setPairing] = useState(false);
  const [pairError, setPairError] = useState('');
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

  const remote = status.remote;
  const notice = !status.connected ? '未连接 · 正在寻找 Mac…'
    : !status.authenticated ? '连接已建立，请完成配对'
    : remote?.locked ? 'Mac 已锁定，请在 Mac 上解锁'
    : remote?.paused ? '遥控已暂停，请在 Mac 菜单栏恢复'
    : remote && !remote.accessibility ? '请在 Mac 菜单栏授权辅助功能' : '';
  async function pair(e: Event) {
    e.preventDefault(); setPairing(true); setPairError('');
    try {
      await connection.request('session.pair', { code, deviceName: /iPhone/.test(navigator.userAgent) ? 'iPhone' : 'Phone' });
      setCode('');
    } catch (error) { setPairError((error as Error).message); }
    finally { setPairing(false); }
  }
  async function sendText(e: Event) {
    e.preventDefault(); setSending(true); setFeedback('');
    try { await connection.request('input.text.insert', { text }); setText(''); setFeedback('已发送输入'); }
    catch (error) { setFeedback((error as Error).message); }
    finally { setSending(false); }
  }
  const navigation = <>
    <section class="toolbar" aria-label="浏览器与文本工具">
      <ControlButton action="back" label="后退" icon="left" shortcut />
      <ControlButton action="forward" label="前进" icon="right" shortcut />
      <ControlButton action="reload" label="刷新" icon="reload" shortcut />
      <button class={`control ${textOpen ? 'selected' : ''}`} onClick={() => setTextOpen(!textOpen)} disabled={!connection.enabled} aria-label="输入文本"><Icon name="keyboard" /><small>输入</small></button>
    </section>
    <div class="quick-tools">
      <ControlButton action="address" label="地址栏" shortcut />
      <ControlButton action="previousTab" label="上一标签" shortcut />
      <ControlButton action="nextTab" label="下一标签" shortcut />
      <ControlButton action="switchApp" label="⌘ Tab" shortcut />
    </div>
  </>;

  return <main class={`shell ${remote?.layout ?? 'generic'}`}>
    <header class="header">
      <div class="brand"><Icon name="remote" /><span>gimme<span class="brand-dot">.</span></span></div>
      <button class={`target ${connection.enabled ? 'online' : ''}`} onClick={() => setSettings(!settings)} aria-label="连接状态和触控板设置">
        <i /><span>{remote?.appName ?? '你的 Mac'}</span><span class="chevron">⌄</span>
      </button>
    </header>
    <div class="eyebrow"><span>THE COUCH IS YOURS.</span><span>REMOTE / 01</span></div>
    {(notice || status.error) && <div class="notice" role="status">
      {notice || status.error}
      {status.error && notice && <small>{status.error}</small>}
    </div>}
    {!status.authenticated && <section class="pair-panel">
      <span class="section-label">HELLO, REMOTE.</span>
      <h1>遥控器给我。</h1>
      <p>手机与 Mac 连接同一 Wi-Fi。打开 Mac 菜单栏的 Gimme Remote，扫描二维码或输入六位配对码。</p>
      <form onSubmit={pair}>
        <label for="pair-code">配对码</label>
        <div class="pair-input"><input id="pair-code" autoComplete="one-time-code" inputMode="numeric" pattern="[0-9]{6}" maxLength={6}
          value={code} onInput={e => setCode(e.currentTarget.value.replace(/\D/g, ''))} placeholder="000000" required />
          <button class="primary" disabled={!status.connected || code.length !== 6 || pairing}>{pairing ? '配对中…' : '连接 Mac'}</button></div>
        {pairError && <p role="alert" class="error">{pairError}</p>}
      </form>
      <small>只发送操作，不传输电视画面。</small>
    </section>}
    {settings && <section class="settings">
      <div class="section-top"><span class="section-label">手感设置</span><button class="text-button" onClick={() => setSettings(false)}>完成</button></div>
      <label for="speed">指针速度 <strong>{speed.toFixed(1)}×</strong></label>
      <input id="speed" type="range" min="0.5" max="3" step="0.1" value={speed} onInput={e => setSpeed(Number(e.currentTarget.value))} />
      <label class="checkbox"><input type="checkbox" checked={acceleration} onChange={e => setAcceleration(e.currentTarget.checked)} />指针加速</label>
      <p>Safari → 分享 → 添加到主屏幕，下次一键打开。</p>
    </section>}
    <section class="remote-panel" aria-label="播放器遥控">
      <div class="section-top"><span class="section-label">{remote?.layout === 'iina' ? 'IINA PLAYER' : remote?.layout === 'browser' ? 'BROWSER PLAYER' : 'PLAYER CONTROL'}</span><span class="hint">看电视，随手操作</span></div>
      <div class="transport">
        <ControlButton action="seekBackward" label="后退" icon="back" repeat />
        <ControlButton action="playPause" label="播放 / 暂停" icon="play" className="play" />
        <ControlButton action="seekForward" label="快进" icon="next" repeat />
      </div>
      <div class="media-tools">
        <ControlButton action="volumeDown" label="音量 −" icon="minus" repeat />
        <ControlButton action="volumeUp" label="音量 +" icon="plus" repeat />
        <ControlButton action="mute" label="静音" icon="mute" />
        <ControlButton action="fullscreen" label="全屏" icon="fullscreen" />
        <ControlButton action="escape" label="Esc" shortcut />
      </div>
      <p class="volume-note">调节播放器音量 · 电视总音量用电视遥控器</p>
    </section>
    {remote?.layout === 'browser' && navigation}
    <Touchpad speed={speed} acceleration={acceleration} />
    {remote?.layout !== 'browser' && navigation}
    {textOpen && <form class="text-panel" onSubmit={sendText}>
      <label for="remote-text">输入到 Mac 当前焦点</label>
      <textarea id="remote-text" rows={3} value={text} onInput={e => setText(e.currentTarget.value)} placeholder="中文搜索词、网址或任何文字…" />
      <div class="text-actions"><ControlButton action="enter" label="回车" shortcut />
        <button class="primary" disabled={!connection.enabled || !text || sending || new TextEncoder().encode(text).length > 8192}>{sending ? '发送中…' : '发送整段文字'}</button></div>
      <span role="status" class="feedback">{feedback}</span>
    </form>}
    <footer><span>GIMME REMOTE</span><span>少起身，多看一会。</span></footer>
  </main>;
}

render(<App />, document.getElementById('app')!);
