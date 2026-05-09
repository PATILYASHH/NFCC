'use client';

import { useEffect, useState } from 'react';

export default function Home() {
  const [scrolled, setScrolled] = useState(false);
  const [actionTab, setActionTab] = useState('phone');

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 16);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });

    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (e.isIntersecting) {
            e.target.classList.add('in');
            io.unobserve(e.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: '0px 0px -60px 0px' }
    );
    document.querySelectorAll('.reveal').forEach((el) => io.observe(el));

    const mouse = (e) => {
      document.querySelectorAll('.feature').forEach((card) => {
        const r = card.getBoundingClientRect();
        card.style.setProperty('--x', `${e.clientX - r.left}px`);
        card.style.setProperty('--y', `${e.clientY - r.top}px`);
      });
    };
    window.addEventListener('mousemove', mouse);

    return () => {
      window.removeEventListener('scroll', onScroll);
      window.removeEventListener('mousemove', mouse);
      io.disconnect();
    };
  }, []);

  return (
    <>
      <nav className={`nav ${scrolled ? 'scrolled' : ''}`}>
        <div className="container nav-inner">
          <a href="#" className="logo">
            <span className="logo-mark">N</span>
            <span>NFC Control</span>
          </a>
          <div className="nav-links">
            <a href="#features">Features</a>
            <a href="#screenshots">Screens</a>
            <a href="#actions">Actions</a>
            <a href="#architecture">Architecture</a>
            <a href="#roadmap">Roadmap</a>
            <a href="https://github.com/sponsors/PATILYASHH"
               target="_blank" rel="noreferrer"
               className="nav-sponsor">
              <HeartIcon /> Sponsor
            </a>
          </div>
          <a href="#download" className="nav-cta">
            Get the app
          </a>
        </div>
      </nav>

      {/* ========== HERO ========== */}
      <section className="hero">
        <div className="hero-bg" />
        <div className="hero-grid" />
        <div className="container hero-inner">
          <div>
            <div className="hero-badge reveal">
              <span className="dot" />
              v1.5.0 · Released May 2026 · Smart Switch
            </div>
            <h1 className="reveal d1">
              One Tap. <br />
              <span className="accent">Automate. Track. Tick off.</span>
            </h1>
            <p className="lede reveal d2">
              One NFC tap can fire a routine, log a glass of water, complete a
              daily TODO, and launch a folder in VS Code on your PC —
              all at once. Local-first, no cloud, no tracking.
            </p>
            <div className="cta-row reveal d3">
              <a href="#download" className="btn btn-primary">
                <DownloadIcon /> Download for Android
              </a>
              <a href="#how" className="btn btn-ghost">
                See how it works <ArrowIcon />
              </a>
            </div>
          </div>

          <div className="orb-wrap reveal d2">
            <div className="ripple" />
            <div className="ripple" />
            <div className="ripple" />
            <div className="orb">
              <div className="orb-icon">
                <NfcLogo size={96} />
              </div>
            </div>
          </div>
        </div>

        <div className="container">
          <div className="stats">
            <Stat num="60+" lbl="Actions" />
            <Stat num="4" lbl="Smart NFC Modes" />
            <Stat num="0" lbl="Cloud Servers" />
            <Stat num="MIT" lbl="License" />
          </div>
        </div>
      </section>

      {/* ========== HOW IT WORKS ========== */}
      <section className="block" id="how">
        <div className="container">
          <div className="section-head center">
            <span className="eyebrow reveal">How it works</span>
            <h2 className="h2 reveal d1">
              Three steps between <br />a tap and a workflow.
            </h2>
            <p className="sub reveal d2">
              NFC tags store only an ID. Every decision — conditions, branches,
              actions — lives inside the app, fully editable and offline-ready.
            </p>
          </div>

          <div className="steps">
            <div className="step reveal d1">
              <div className="step-icon">
                <TagIcon color="#00B0FF" />
              </div>
              <h3>Tap a tag</h3>
              <p>
                Stick an NFC tag anywhere — desk, wall, keychain. One tap reads
                its unique UID in under a second.
              </p>
              <StepArrow />
            </div>

            <div className="step reveal d2">
              <div className="step-icon">
                <BranchIcon color="#8B5CF6" />
              </div>
              <h3>Evaluate context</h3>
              <p>
                Time of day, weekday, current Wi-Fi, Bluetooth state — IF/ELSE
                branches pick the right response automatically.
              </p>
              <StepArrow />
            </div>

            <div className="step reveal d3">
              <div className="step-icon">
                <BoltIcon color="#10B981" />
              </div>
              <h3>Execute everywhere</h3>
              <p>
                Fire phone actions, toggle PC apps, adjust volume, launch IDEs
                — one tap, two devices, zero friction.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* ========== FEATURES ========== */}
      <section className="block" id="features" style={{ paddingTop: 40 }}>
        <div className="container">
          <div className="section-head center">
            <span className="eyebrow reveal">Why NFCC</span>
            <h2 className="h2 reveal d1">Built for real workflows.</h2>
            <p className="sub reveal d2">
              Not another toy. Every feature here exists because a routine
              needed it — offline reliability, deep context, and true
              cross-device control.
            </p>
          </div>

          <div className="features">
            {FEATURES.map((f, i) => (
              <div
                className={`feature reveal d${(i % 6) + 1}`}
                key={f.title}
              >
                <div
                  className="feature-ic"
                  style={{
                    background: `${f.color}15`,
                    border: `1px solid ${f.color}40`,
                    color: f.color,
                  }}
                >
                  {f.icon}
                </div>
                <h3>{f.title}</h3>
                <p>{f.body}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ========== DUAL SHOWCASE ========== */}
      <section className="block">
        <div className="container">
          <div className="section-head center">
            <span className="eyebrow reveal">Two apps, one brain</span>
            <h2 className="h2 reveal d1">Phone + PC, perfectly paired.</h2>
            <p className="sub reveal d2">
              Scan a QR, pair over local Wi-Fi, and command your desktop from
              your pocket. No cloud, no accounts, no latency.
            </p>
          </div>

          <div className="dual">
            <div className="showcase phone reveal d1">
              <div className="tag">
                <span>◇</span> Mobile · Flutter
              </div>
              <h3>The Brain</h3>
              <p>
                Create automations, write NFC tags, and track every tap. A
                Samsung-inspired dark UI built for one-handed use.
              </p>
              <ul className="list">
                <li>
                  <CheckIcon /> Read, write, format NTAG213/215/216
                </li>
                <li>
                  <CheckIcon /> IF/ELSE branches with live preview
                </li>
                <li>
                  <CheckIcon /> 28 phone actions + scan history
                </li>
                <li>
                  <CheckIcon /> Offline SQLite — works without internet
                </li>
              </ul>
              <div className="showcase-art">
                <PhoneMock />
              </div>
            </div>

            <div className="showcase pc reveal d2">
              <div className="tag">
                <span>◇</span> Desktop · Python
              </div>
              <h3>The Muscle</h3>
              <p>
                A lightweight system-tray companion that listens for commands
                and executes them instantly. Auto-discovery over UDP.
              </p>
              <ul className="list">
                <li>
                  <CheckIcon /> 33 PC actions — incl. Smart Switch handoff
                </li>
                <li>
                  <CheckIcon /> Editable mapping table (web dashboard, JSON)
                </li>
                <li>
                  <CheckIcon /> WebSocket server over local Wi-Fi
                </li>
                <li>
                  <CheckIcon /> QR pairing with auto-discovery
                </li>
                <li>
                  <CheckIcon /> System-tray icon, optional autostart
                </li>
              </ul>
              <div className="showcase-art">
                <PcMock />
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ========== SCREENSHOTS ========== */}
      <section className="block tinted-block" id="screenshots">
        <div className="container">
          <div className="section-head center">
            <span className="eyebrow reveal">Screens</span>
            <h2 className="h2 reveal d1">Shot on device, not mocked up.</h2>
            <p className="sub reveal d2">
              Every pixel below is the current Android build. Dark Samsung-inspired
              theme, one-handed friendly, haptic feedback on every tap.
            </p>
          </div>

          <div className="shots">
            {SHOTS.map((s, i) => (
              <figure
                key={s.src}
                className={`shot reveal d${Math.min(i + 1, 6)}`}
              >
                <div className="shot-frame">
                  <img src={s.src} alt={s.caption} loading="lazy" />
                </div>
                <figcaption>
                  <span className="shot-num">0{i + 1}</span>
                  <span className="shot-cap">{s.caption}</span>
                </figcaption>
              </figure>
            ))}
          </div>
        </div>
      </section>

      {/* ========== ACTIONS ========== */}
      <section className="block" id="actions">
        <div className="container">
          <div className="section-head center">
            <span className="eyebrow reveal">Action library</span>
            <h2 className="h2 reveal d1">60+ actions, one orchestrator.</h2>
            <p className="sub reveal d2">
              Chain any combination. Reorder with a drag. Each automation runs
              actions sequentially with smart delays.
            </p>
            <div
              className="tabs-bar reveal d2"
              style={{ margin: '0 auto 32px' }}
            >
              <button
                className={`tab-btn ${actionTab === 'phone' ? 'active' : ''}`}
                onClick={() => setActionTab('phone')}
              >
                Phone · 28
              </button>
              <button
                className={`tab-btn ${actionTab === 'pc' ? 'active' : ''}`}
                onClick={() => setActionTab('pc')}
              >
                PC · 33
              </button>
            </div>
          </div>

          <div className="actions-grid">
            {(actionTab === 'phone' ? PHONE_ACTIONS : PC_ACTIONS).map(
              (a, i) => (
                <div
                  className="action-chip reveal"
                  key={a.name}
                  style={{ transitionDelay: `${Math.min(i * 30, 500)}ms` }}
                >
                  <span
                    className="action-ic"
                    style={{ background: `${a.color}18`, color: a.color }}
                  >
                    {a.ic}
                  </span>
                  {a.name}
                </div>
              )
            )}
          </div>
        </div>
      </section>

      {/* ========== ARCHITECTURE ========== */}
      <section className="block" id="architecture">
        <div className="container">
          <div className="section-head center">
            <span className="eyebrow reveal">Architecture</span>
            <h2 className="h2 reveal d1">Local-first. Zero cloud.</h2>
            <p className="sub reveal d2">
              Everything runs on your LAN. NFC tags only store a UID — all
              logic, routing, and state stays on your devices.
            </p>
          </div>

          <div className="arch reveal d1">
            <div className="arch-row">
              <div className="arch-node">
                <div className="t">Step 1</div>
                <div className="n">NFC Tag</div>
                <div className="d">
                  NTAG213 / 215 / 216. Stores only the UID.
                </div>
              </div>
              <div className="arch-arrow">→</div>
              <div className="arch-node">
                <div className="t">Step 2</div>
                <div className="n">Phone App</div>
                <div className="d">
                  Matches UID → evaluates branches → fires actions.
                </div>
              </div>
              <div className="arch-arrow">→</div>
              <div className="arch-node">
                <div className="t">Step 3</div>
                <div className="n">PC Companion</div>
                <div className="d">
                  WebSocket receiver executes desktop actions.
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ========== ROADMAP ========== */}
      <section className="block" id="roadmap">
        <div className="container">
          <div className="section-head center">
            <span className="eyebrow reveal">Roadmap</span>
            <h2 className="h2 reveal d1">Shipped, and still shipping.</h2>
            <p className="sub reveal d2">
              Five phases complete. The v1.0 release is polished and ready —
              the next phases bring richer conditions and cloud sync.
            </p>
          </div>

          <div className="phases">
            {PHASES.map((p) => (
              <div
                className={`phase reveal ${p.status}`}
                key={p.num}
              >
                <span className="phase-num">PHASE {p.num}</span>
                <span className={`phase-check ${p.status === 'wait' ? 'wait' : ''}`}>
                  {p.status === 'done' ? '✓' : p.status === 'active' ? '●' : '○'}
                </span>
                <h4>{p.title}</h4>
                <p>{p.body}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ========== DOWNLOADS ========== */}
      <section className="block" id="download">
        <div className="container">
          <div className="section-head center">
            <span className="eyebrow reveal">Download</span>
            <h2 className="h2 reveal d1">Get NFCC for your platform.</h2>
            <p className="sub reveal d2">
              Open source and MIT licensed. Every build is produced by GitHub Actions from the{' '}
              <a
                href="https://github.com/PATILYASHH/nfcc"
                style={{ color: '#00B0FF' }}
              >
                main branch
              </a>
              .
            </p>
          </div>

          <div className="download-grid">
            {DOWNLOADS.map((d) => (
              <a
                key={d.name}
                href={d.href}
                target="_blank"
                rel="noreferrer"
                className={`download-card reveal ${d.status === 'planned' ? 'planned' : ''}`}
              >
                <div
                  className="download-ic"
                  style={{
                    background: `${d.color}18`,
                    color: d.color,
                    border: `1px solid ${d.color}40`,
                  }}
                >
                  {d.icon}
                </div>
                <div className="download-meta">
                  <div className="download-name">{d.name}</div>
                  <div className="download-file">{d.file}</div>
                </div>
                <span
                  className="download-cta"
                  style={{
                    color: d.status === 'planned' ? '#6B7280' : d.color,
                  }}
                >
                  {d.status === 'planned' ? 'Planned' : 'Download ↓'}
                </span>
              </a>
            ))}
          </div>

          <div className="download-foot reveal">
            <a
              href="https://github.com/PATILYASHH/nfcc"
              target="_blank"
              rel="noreferrer"
              className="btn btn-ghost"
            >
              <GithubIcon /> Source on GitHub
            </a>
            <a
              href="https://github.com/PATILYASHH/nfcc/releases/latest"
              target="_blank"
              rel="noreferrer"
              className="btn btn-ghost"
            >
              <DownloadIcon /> All releases
            </a>
          </div>
        </div>
      </section>

      {/* ========== SPONSOR ========== */}
      <section className="block" id="sponsor">
        <div className="container">
          <div className="sponsor-card reveal">
            <div className="sponsor-ic"><HeartIcon /></div>
            <div className="sponsor-copy">
              <div className="eyebrow" style={{ marginBottom: 6 }}>Support the project</div>
              <h3>Keep NFCC free & open-source.</h3>
              <p>
                NFCC is MIT, ad-free, tracker-free, and paid for out of pocket.
                If it saves you time, a monthly sponsorship keeps the releases
                and the next features shipping.
              </p>
            </div>
            <a
              href="https://github.com/sponsors/PATILYASHH"
              target="_blank"
              rel="noreferrer"
              className="btn btn-primary"
            >
              <HeartIcon /> Sponsor on GitHub
            </a>
          </div>
        </div>
      </section>

      <footer>
        <div className="container footer-inner">
          <div>
            <div className="logo" style={{ marginBottom: 6 }}>
              <span className="logo-mark">N</span>
              <span>NFC Control</span>
            </div>
            <div>© 2026 NFCC · Built by Yash · Local-first, cloud-free.</div>
          </div>
          <div className="footer-links">
            <a href="#features">Features</a>
            <a href="#how">How</a>
            <a href="#actions">Actions</a>
            <a href="#architecture">Architecture</a>
            <a
              href="https://github.com/sponsors/PATILYASHH"
              target="_blank"
              rel="noreferrer"
            >
              Sponsor
            </a>
          </div>
        </div>
      </footer>
    </>
  );
}

/* ========================= Data ========================= */

const FEATURES = [
  {
    title: 'Smart Switch · NEW',
    body: 'Tap a tag and your PC picks up exactly what you were doing — YouTube at the same timestamp (incl. ReVanced), Spotify track, browser tab, WhatsApp chat with the draft auto-pasted. Per-app mapping table editable from the PC dashboard.',
    color: '#00E5FF',
    icon: <SwapIcon />,
  },
  {
    title: 'Routines',
    body: 'IF/ELSE automations over time, weekday, Wi-Fi SSID, and Bluetooth state. Chain phone + PC actions per branch.',
    color: '#00B0FF',
    icon: <BranchIcon />,
  },
  {
    title: 'Tracking',
    body: 'Counters (water, coffee, calories) and state-aware IN / OUT toggles (home, office, gym). Goals, streaks, logs.',
    color: '#22D3EE',
    icon: <LogIcon />,
  },
  {
    title: 'TODOs',
    body: 'Daily tasks with streak counters or one-off lists. Optional reminder time. Tap a paired tag to complete.',
    color: '#8B5CF6',
    icon: <SparkIcon />,
  },
  {
    title: 'One tag, many jobs',
    body: 'A single tag can fire a routine, log multiple trackers, and tick off several TODOs in one tap.',
    color: '#EC4899',
    icon: <TagIcon />,
  },
  {
    title: 'Write any NFC payload',
    body: 'URL, Wi-Fi, SMS, email, phone, location (map picker), app launcher, UPI payment links — NTAG213/215/216.',
    color: '#F97316',
    icon: <ReorderIcon />,
  },
  {
    title: 'Rich PC App Picker',
    body: '22 preset PC apps (VS Code, Chrome, Terminal, Explorer, …). Pass a folder path to open it in VS Code on one tap.',
    color: '#3B82F6',
    icon: <LinkIcon />,
  },
  {
    title: 'Auto PC reconnect',
    body: 'Phone survives WiFi hops and DHCP renewals — UDP rediscovery refreshes the stored IP within seconds.',
    color: '#F59E0B',
    icon: <RadarIcon />,
  },
  {
    title: 'NFCC-PC terminal CLI',
    body: 'One binary, status/pair/dashboard/reconnect/forward/action from any terminal. UPnP port forwarding included.',
    color: '#EF4444',
    icon: <TrayIcon />,
  },
  {
    title: 'Local-first SQLite',
    body: 'Every tag, log, TODO, and tracker lives on your device. No account, no analytics, no tracking — F-Droid ready.',
    color: '#10B981',
    icon: <DatabaseIcon />,
  },
];

const PHONE_ACTIONS = [
  { name: 'Toggle Wi-Fi', ic: '📶', color: '#3B82F6' },
  { name: 'Toggle Bluetooth', ic: '🔵', color: '#22D3EE' },
  { name: 'Silent Mode', ic: '🔕', color: '#A0A4AE' },
  { name: 'Do Not Disturb', ic: '🌙', color: '#8B5CF6' },
  { name: 'Torch On/Off', ic: '🔦', color: '#F59E0B' },
  { name: 'Set Brightness', ic: '☀️', color: '#F97316' },
  { name: 'Adjust Volume', ic: '🔊', color: '#10B981' },
  { name: 'Open URL', ic: '🌐', color: '#00B0FF' },
  { name: 'Launch App', ic: '📱', color: '#EC4899' },
  { name: 'Send SMS', ic: '💬', color: '#10B981' },
  { name: 'Make Call', ic: '📞', color: '#3B82F6' },
  { name: 'Copy to Clipboard', ic: '📋', color: '#A0A4AE' },
  { name: 'Play Music', ic: '🎵', color: '#EC4899' },
  { name: 'Pause Media', ic: '⏸', color: '#8B5CF6' },
  { name: 'Toggle Flight Mode', ic: '✈️', color: '#22D3EE' },
  { name: 'Speak Text (TTS)', ic: '🗣', color: '#F97316' },
  { name: 'Show Notification', ic: '🔔', color: '#F59E0B' },
  { name: 'Vibrate', ic: '📳', color: '#EF4444' },
  { name: 'Open Camera', ic: '📷', color: '#00B0FF' },
  { name: 'Open Maps', ic: '🗺', color: '#10B981' },
  { name: 'Share Location', ic: '📍', color: '#EC4899' },
  { name: 'Start Timer', ic: '⏱', color: '#F59E0B' },
  { name: 'Set Alarm', ic: '⏰', color: '#F97316' },
  { name: 'Add Todo', ic: '✅', color: '#10B981' },
  { name: 'Tracker Log', ic: '📊', color: '#8B5CF6' },
  { name: 'Start Recording', ic: '🎙', color: '#EF4444' },
  { name: 'Run Tasker Job', ic: '⚡', color: '#00B0FF' },
  { name: 'Custom Intent', ic: '🧩', color: '#3B82F6' },
];

const PC_ACTIONS = [
  { name: 'Smart Switch Handoff', ic: '↔', color: '#00E5FF' },
  { name: 'Launch Application', ic: '🚀', color: '#00B0FF' },
  { name: 'Close Window', ic: '✕', color: '#EF4444' },
  { name: 'Minimize All', ic: '➖', color: '#A0A4AE' },
  { name: 'Show Desktop', ic: '🖥', color: '#3B82F6' },
  { name: 'Lock Workstation', ic: '🔒', color: '#8B5CF6' },
  { name: 'Sleep PC', ic: '💤', color: '#22D3EE' },
  { name: 'Shutdown', ic: '⏻', color: '#EF4444' },
  { name: 'Restart', ic: '🔄', color: '#F59E0B' },
  { name: 'Set Volume', ic: '🔊', color: '#10B981' },
  { name: 'Mute / Unmute', ic: '🔇', color: '#A0A4AE' },
  { name: 'Play / Pause', ic: '⏯', color: '#EC4899' },
  { name: 'Next Track', ic: '⏭', color: '#EC4899' },
  { name: 'Previous Track', ic: '⏮', color: '#EC4899' },
  { name: 'Open URL', ic: '🌐', color: '#00B0FF' },
  { name: 'Open File / Folder', ic: '📂', color: '#F59E0B' },
  { name: 'Run Command', ic: '⌨️', color: '#8B5CF6' },
  { name: 'Run PowerShell', ic: '⚡', color: '#3B82F6' },
  { name: 'Paste Text', ic: '📋', color: '#A0A4AE' },
  { name: 'Type Keystrokes', ic: '⌨', color: '#F97316' },
  { name: 'Hotkey Combo', ic: '🎹', color: '#8B5CF6' },
  { name: 'Screenshot', ic: '📸', color: '#EC4899' },
  { name: 'Toggle Mic Mute', ic: '🎙', color: '#EF4444' },
  { name: 'Webcam Toggle', ic: '📷', color: '#00B0FF' },
  { name: 'Change Brightness', ic: '💡', color: '#F59E0B' },
  { name: 'Night Light', ic: '🌙', color: '#8B5CF6' },
  { name: 'Launch IDE', ic: '💻', color: '#22D3EE' },
  { name: 'Send Notification', ic: '🔔', color: '#F97316' },
  { name: 'Focus Window', ic: '🎯', color: '#10B981' },
  { name: 'Move Window', ic: '↔️', color: '#3B82F6' },
  { name: 'Toggle Fullscreen', ic: '⛶', color: '#A0A4AE' },
  { name: 'Start Stream', ic: '📡', color: '#EF4444' },
  { name: 'Custom Script', ic: '🧩', color: '#00B0FF' },
];

const SHOTS = [
  {
    src: '/screenshots/01-smart-nfc-hub.png',
    caption: 'Smart NFC hub — Routines, Tracking, TODOs in one place',
  },
  {
    src: '/screenshots/02-nfc-writer.png',
    caption: 'NFC Writer — URL, Wi-Fi, UPI, location, app launcher',
  },
  {
    src: '/screenshots/03-automation-editor.png',
    caption: 'IF / ELSE automation editor with live conditions',
  },
  {
    src: '/screenshots/04-nfc-scan.png',
    caption: 'Tap feedback — haptic confirmation on every scan',
  },
];

const DOWNLOADS = [
  {
    name: 'Android',
    file: 'app-release.apk',
    color: '#10B981',
    href: 'https://github.com/PATILYASHH/nfcc/releases/latest',
    icon: <AndroidIcon />,
  },
  {
    name: 'Windows · PC Companion',
    file: 'NFCC-Companion.exe',
    color: '#00B0FF',
    href: 'https://github.com/PATILYASHH/nfcc/releases/latest',
    icon: <WindowsIcon />,
  },
  {
    name: 'iOS · developer preview',
    file: 'NFCC-Runner.app.zip',
    color: '#A0A4AE',
    href: 'https://github.com/PATILYASHH/nfcc/actions/workflows/ios.yml',
    icon: <AppleIcon />,
  },
  {
    name: 'macOS',
    file: 'coming soon',
    status: 'planned',
    color: '#6B7280',
    href: 'https://github.com/PATILYASHH/nfcc/issues',
    icon: <AppleIcon />,
  },
  {
    name: 'Linux',
    file: 'coming soon',
    status: 'planned',
    color: '#6B7280',
    href: 'https://github.com/PATILYASHH/nfcc/issues',
    icon: <LinuxIcon />,
  },
];

const PHASES = [
  {
    num: '01',
    status: 'done',
    title: 'Foundation · v1.0',
    body: 'Flutter scaffold, Samsung theme, SQLite schema, NFC read/write/format.',
  },
  {
    num: '02',
    status: 'done',
    title: 'Automation Engine · v1.0',
    body: 'IF/ELSE branches over time / weekday / Wi-Fi / Bluetooth. 28 phone actions.',
  },
  {
    num: '03',
    status: 'done',
    title: 'PC Companion · v1.0',
    body: 'Python tray, WebSocket, 32 actions, UDP discovery, QR pair.',
  },
  {
    num: '04',
    status: 'done',
    title: 'Smart NFC Hub · v1.1',
    body: 'Routines + Tracking (counters + IN/OUT) + TODOs (streaks + reminder time).',
  },
  {
    num: '05',
    status: 'done',
    title: 'Cross-install tags · v1.1',
    body: 'NFCC_T: / NFCC_D: NDEF so one physical tag re-pairs on any device.',
  },
  {
    num: '06',
    status: 'done',
    title: 'PC CLI + UPnP · v1.1',
    body: 'NFCC-PC terminal command, port fallback, auto-reconnect, UPnP forwarding.',
  },
  {
    num: '07',
    status: 'done',
    title: 'Pair once, stay paired · v1.2',
    body: 'Auto-reconnect on launch, multi-NIC discovery fix, bulletproof service detach, NFCC-PC health.',
  },
  {
    num: '08',
    status: 'done',
    title: 'Smart Switch · v1.5',
    body: 'Foreground-app handoff to PC: YouTube/ReVanced timestamp, Spotify, browser tab, WhatsApp draft. Editable mapping table on the PC dashboard.',
  },
];

/* ========================= Components ========================= */

function Stat({ num, lbl }) {
  return (
    <div className="stat reveal">
      <div className="num">{num}</div>
      <div className="lbl">{lbl}</div>
    </div>
  );
}

function StepArrow() {
  return (
    <span className="step-arrow" aria-hidden>
      <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
        <path
          d="M6 14h16m0 0-6-6m6 6-6 6"
          stroke="currentColor"
          strokeWidth="1.5"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    </span>
  );
}

function PhoneMock() {
  return (
    <div className="phone-mock">
      <div className="phone-screen">
        <div
          style={{
            fontSize: 13,
            fontWeight: 800,
            letterSpacing: '-0.3px',
            marginBottom: 6,
          }}
        >
          NFCC
        </div>
        <div className="mini-card">
          <div>
            <div>🌅 Morning Office</div>
            <div className="m">8 actions · IF weekday</div>
          </div>
          <span className="mini-pill">ON</span>
        </div>
        <div className="mini-card">
          <div>
            <div>🍽 Lunch Break</div>
            <div className="m">3 actions · time based</div>
          </div>
          <span className="mini-pill">ON</span>
        </div>
        <div className="mini-card">
          <div>
            <div>🌙 Leave Work</div>
            <div className="m">5 actions · IF wifi</div>
          </div>
          <span className="mini-pill">ON</span>
        </div>
        <div
          style={{
            marginTop: 'auto',
            textAlign: 'center',
            padding: '8px 0',
            background: '#fff',
            color: '#000',
            borderRadius: 10,
            fontSize: 11,
            fontWeight: 700,
          }}
        >
          + New Automation
        </div>
      </div>
    </div>
  );
}

function PcMock() {
  return (
    <div className="pc-mock">
      <div className="pc-bar">
        <span />
        <span />
        <span />
      </div>
      <div className="pc-window">
        <span className="line">
          <span className="c"># NFCC companion</span>
        </span>
        <span className="line">
          <span className="k">[listen]</span>{' '}
          <span className="s">ws://192.168.0.14:8787</span>
        </span>
        <span className="line">
          <span className="k">[pair]</span>{' '}
          <span className="s">yash-pixel-8 OK</span>
        </span>
        <span className="line">
          <span className="k">[recv]</span> tag:OFFICE_MORNING
        </span>
        <span className="line">
          <span className="c">  → launch vscode</span>
        </span>
        <span className="line">
          <span className="c">  → open localhost:3000</span>
        </span>
        <span className="line">
          <span className="c">  → set volume 40</span>
        </span>
        <span className="line">
          <span className="k">[done]</span>{' '}
          <span className="s">342 ms</span>
        </span>
      </div>
    </div>
  );
}

/* ========================= Icons ========================= */

function NfcLogo({ size = 24 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 48 48" fill="none">
      <path
        d="M12 14c4 2 7 5 9 9 2 4 3 7 3 11"
        stroke="currentColor"
        strokeWidth="2.5"
        strokeLinecap="round"
      />
      <path
        d="M18 10c6 2 11 7 13 13 2 6 2 11 1 15"
        stroke="currentColor"
        strokeWidth="2.5"
        strokeLinecap="round"
        opacity="0.75"
      />
      <path
        d="M24 6c8 2 14 10 16 17 2 7 1 13-1 19"
        stroke="currentColor"
        strokeWidth="2.5"
        strokeLinecap="round"
        opacity="0.5"
      />
    </svg>
  );
}

function TagIcon({ color = 'currentColor' }) {
  return (
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
      <path
        d="M4 13V5a2 2 0 0 1 2-2h8l7 7-9 9a2 2 0 0 1-2.8 0L4 13.5"
        stroke={color}
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <circle cx="9" cy="8" r="1.4" fill={color} />
    </svg>
  );
}

function BranchIcon({ color = 'currentColor' }) {
  return (
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
      <circle cx="6" cy="5" r="2" stroke={color} strokeWidth="1.6" />
      <circle cx="6" cy="19" r="2" stroke={color} strokeWidth="1.6" />
      <circle cx="18" cy="12" r="2" stroke={color} strokeWidth="1.6" />
      <path
        d="M6 7v3a3 3 0 0 0 3 3h7M6 17v-3"
        stroke={color}
        strokeWidth="1.6"
        strokeLinecap="round"
      />
    </svg>
  );
}

function BoltIcon({ color = 'currentColor' }) {
  return (
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
      <path
        d="M13 2 4 14h7l-1 8 9-12h-7l1-8Z"
        stroke={color}
        strokeWidth="1.6"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function LinkIcon({ color = 'currentColor' }) {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
      <path
        d="M9 15l6-6m-4-4 1-1a4 4 0 0 1 6 6l-1 1M13 19l-1 1a4 4 0 0 1-6-6l1-1"
        stroke={color}
        strokeWidth="1.7"
        strokeLinecap="round"
      />
    </svg>
  );
}

function DatabaseIcon({ color = 'currentColor' }) {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
      <ellipse cx="12" cy="5" rx="8" ry="3" stroke={color} strokeWidth="1.6" />
      <path
        d="M4 5v14c0 1.7 3.6 3 8 3s8-1.3 8-3V5M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"
        stroke={color}
        strokeWidth="1.6"
      />
    </svg>
  );
}

function LogIcon({ color = 'currentColor' }) {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
      <path
        d="M5 4h14v16H5zM8 9h8M8 13h8M8 17h5"
        stroke={color}
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function SparkIcon({ color = 'currentColor' }) {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
      <path
        d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l3 3M15 15l3 3M18 6l-3 3M9 15l-3 3"
        stroke={color}
        strokeWidth="1.6"
        strokeLinecap="round"
      />
    </svg>
  );
}

function RadarIcon({ color = 'currentColor' }) {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
      <circle cx="12" cy="12" r="9" stroke={color} strokeWidth="1.6" />
      <circle cx="12" cy="12" r="5" stroke={color} strokeWidth="1.6" opacity="0.6" />
      <path
        d="M12 12l6-3"
        stroke={color}
        strokeWidth="1.6"
        strokeLinecap="round"
      />
      <circle cx="12" cy="12" r="1.5" fill={color} />
    </svg>
  );
}

function ReorderIcon({ color = 'currentColor' }) {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
      <path
        d="M4 7h12M4 12h12M4 17h12M20 5v14M17 8l3-3 3 3M17 16l3 3 3-3"
        stroke={color}
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function SwapIcon({ color = 'currentColor' }) {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
      <path
        d="M4 8h13m0 0-4-4m4 4-4 4M20 16H7m0 0 4 4m-4-4 4-4"
        stroke={color}
        strokeWidth="1.7"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function TrayIcon({ color = 'currentColor' }) {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
      <rect x="3" y="4" width="18" height="13" rx="2" stroke={color} strokeWidth="1.6" />
      <path d="M8 20h8M12 17v3" stroke={color} strokeWidth="1.6" strokeLinecap="round" />
      <circle cx="17" cy="10.5" r="1" fill={color} />
    </svg>
  );
}

function DownloadIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
      <path
        d="M12 3v12m0 0 4-4m-4 4-4-4M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function ArrowIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
      <path
        d="M5 12h14m0 0-5-5m5 5-5 5"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function WindowsIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
      <path d="M3 5.1 10.5 4v7.5H3zM11.5 3.85 21 2.5V11.5h-9.5zM3 12.5h7.5V20L3 18.9zM11.5 12.5H21V21.5L11.5 20.15z" />
    </svg>
  );
}

function AndroidIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor">
      <path d="M17.5 9.5 19 7l-1-.5-1.5 2.5A7.9 7.9 0 0 0 12 8a7.9 7.9 0 0 0-4.5 1L6 6.5 5 7l1.5 2.5A6.9 6.9 0 0 0 4 15h16a6.9 6.9 0 0 0-2.5-5.5ZM8.5 13a1 1 0 1 1 0-2 1 1 0 0 1 0 2Zm7 0a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"/>
    </svg>
  );
}

function AppleIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
      <path d="M16.8 12.3c0-2.6 2.1-3.8 2.2-3.9-1.2-1.7-3-1.9-3.7-2-1.6-.2-3 .9-3.8.9-.8 0-2-.9-3.3-.9-1.7 0-3.2 1-4.1 2.5-1.7 3-.4 7.5 1.3 10 .8 1.2 1.8 2.6 3 2.5 1.2-.1 1.7-.8 3.1-.8 1.5 0 1.9.8 3.2.8 1.3 0 2.2-1.2 3-2.5.9-1.4 1.3-2.8 1.3-2.9-.1 0-2.5-.9-2.2-3.7ZM14.5 4.8c.7-.8 1.1-1.9 1-3-.9.1-2.1.6-2.8 1.4-.7.7-1.2 1.9-1.1 2.9 1 .1 2.1-.5 2.9-1.3Z"/>
    </svg>
  );
}

function LinuxIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
      <path d="M12 2c-2.2 0-4 2.5-4 6 0 1.4.3 2.6.8 3.5-.7.8-1.6 1.6-2.3 2.3-1 1.2-1.5 2.4-1.5 3.2 0 .6.3 1 .7 1.3.3.1.4.3.4.8 0 .6.3 1.1.8 1.4.4.2.7.5.9.9.3.6.8.9 1.6.9.5 0 1.1-.2 1.5-.5.4-.4.9-.5 1.4-.5s1 .1 1.4.5c.4.3 1 .5 1.5.5.8 0 1.3-.3 1.6-.9.2-.4.5-.7.9-.9.5-.3.8-.8.8-1.4 0-.5.1-.7.4-.8.4-.3.7-.7.7-1.3 0-.8-.5-2-1.5-3.2-.7-.7-1.6-1.5-2.3-2.3.5-.9.8-2.1.8-3.5 0-3.5-1.8-6-4-6Zm-1.5 4.5c.3 0 .6.4.6 1s-.3 1-.6 1-.6-.4-.6-1 .3-1 .6-1Zm3 0c.3 0 .6.4.6 1s-.3 1-.6 1-.6-.4-.6-1 .3-1 .6-1Z"/>
    </svg>
  );
}

function HeartIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
      <path d="M12 21s-7-4.5-9.5-9A5.5 5.5 0 0 1 12 6a5.5 5.5 0 0 1 9.5 6C19 16.5 12 21 12 21Z" />
    </svg>
  );
}

function GithubIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
      <path d="M12 2a10 10 0 0 0-3.2 19.5c.5.1.7-.2.7-.5v-2c-2.8.6-3.4-1.2-3.4-1.2-.4-1.1-1.1-1.4-1.1-1.4-.9-.6.1-.6.1-.6 1 .1 1.6 1 1.6 1 .9 1.5 2.3 1.1 2.9.8.1-.6.3-1.1.6-1.3-2.2-.3-4.6-1.1-4.6-5 0-1.1.4-2 1-2.7-.1-.3-.5-1.3.1-2.6 0 0 .9-.3 2.8 1a9.5 9.5 0 0 1 5 0c1.9-1.3 2.8-1 2.8-1 .6 1.3.2 2.3.1 2.6.7.7 1 1.6 1 2.7 0 3.9-2.4 4.7-4.6 5 .4.3.7.9.7 1.8v2.7c0 .3.2.6.7.5A10 10 0 0 0 12 2Z"/>
    </svg>
  );
}

function GlobeIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
      <circle cx="12" cy="12" r="9" stroke="currentColor" strokeWidth="1.7"/>
      <path d="M3 12h18M12 3c3 3.5 3 14 0 18M12 3c-3 3.5-3 14 0 18" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round"/>
    </svg>
  );
}

function CheckIcon() {
  return (
    <svg
      className="check"
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
    >
      <path
        d="m5 12 5 5L20 7"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
