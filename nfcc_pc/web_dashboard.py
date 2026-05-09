"""Web-based dashboard for NFCC PC companion."""

import json
import socket
import threading
import webbrowser
import base64
from http.server import HTTPServer, BaseHTTPRequestHandler
from io import BytesIO

import qrcode

import installed_apps
import mappings


def get_local_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"
    finally:
        s.close()


def generate_qr_base64(config: dict) -> str:
    data = json.dumps({
        "id": config["id"],
        "name": socket.gethostname(),
        "ip": get_local_ip(),
        "port": config["port"],
        "token": config["pairing_token"],
    })
    qr = qrcode.QRCode(version=1, error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=8, border=2)
    qr.add_data(data)
    qr.make(fit=True)
    img = qr.make_image(fill_color="#00B0FF", back_color="#0D1117")
    buf = BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


class DashboardState:
    """Shared state between websocket server and dashboard."""
    def __init__(self):
        self.connected_devices = []
        self.action_log = []
        self.status = "Waiting for connection..."

    def add_log(self, action: str, success: bool, detail: str = ""):
        import datetime
        self.action_log.insert(0, {
            "time": datetime.datetime.now().strftime("%H:%M:%S"),
            "action": action,
            "success": success,
            "detail": detail,
        })
        if len(self.action_log) > 50:
            self.action_log = self.action_log[:50]


_state = DashboardState()


def get_state():
    return _state


def build_html(config: dict) -> str:
    qr_b64 = generate_qr_base64(config)
    ip = get_local_ip()
    port = config["port"]
    hostname = socket.gethostname()

    return f"""<!DOCTYPE html>
<html lang="en" data-bs-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NFCC - NFC Control</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css" rel="stylesheet">
    <style>
        body {{ background: #0D1117; color: #e6edf3; font-family: 'Segoe UI', system-ui, sans-serif; }}
        .card {{ background: #161B22; border: 1px solid #30363D; border-radius: 16px; }}
        .card-header {{ background: transparent; border-bottom: 1px solid #21262D; }}
        .badge-success {{ background: #22C55E20; color: #22C55E; }}
        .badge-fail {{ background: #EF444420; color: #EF4444; }}
        .badge-info {{ background: #3B82F620; color: #3B82F6; }}
        .status-dot {{ width: 10px; height: 10px; border-radius: 50%; display: inline-block; }}
        .status-dot.online {{ background: #22C55E; box-shadow: 0 0 8px #22C55E80; }}
        .status-dot.offline {{ background: #6B7280; }}
        .qr-container {{ background: #0D1117; border-radius: 12px; padding: 16px; display: inline-block; }}
        .action-list {{ max-height: 400px; overflow-y: auto; }}
        .action-item {{ padding: 10px 14px; border-bottom: 1px solid #21262D; }}
        .action-item:last-child {{ border-bottom: none; }}
        .nfc-icon {{ font-size: 2.5rem; color: #00B0FF; }}
        .stat-card {{ background: #161B22; border: 1px solid #30363D; border-radius: 12px; padding: 16px; text-align: center; }}
        .stat-value {{ font-size: 1.8rem; font-weight: 700; }}
        .stat-label {{ font-size: 0.75rem; color: #8B949E; text-transform: uppercase; letter-spacing: 0.5px; }}
        .header-gradient {{ background: linear-gradient(135deg, #0D1117 0%, #161B22 100%); }}
        a {{ color: #58A6FF; }}
        .refresh-btn {{ cursor: pointer; transition: transform 0.3s; }}
        .refresh-btn:hover {{ transform: rotate(180deg); }}
    </style>
</head>
<body>
    <div class="container py-4" style="max-width: 960px;">
        <!-- Header -->
        <div class="d-flex align-items-center mb-4">
            <i class="bi bi-nfc nfc-icon me-3"></i>
            <div>
                <h3 class="mb-0 fw-bold">NFCC <span class="text-secondary fw-normal fs-6">NFC Control</span></h3>
                <small class="text-secondary">{hostname} &bull; {ip}:{port}</small>
            </div>
            <div class="ms-auto">
                <span id="statusDot" class="status-dot offline me-2"></span>
                <span id="statusText" class="text-secondary">Loading...</span>
            </div>
        </div>

        <!-- Stats Row -->
        <div class="row g-3 mb-4">
            <div class="col-4">
                <div class="stat-card">
                    <div class="stat-value text-info" id="statDevices">0</div>
                    <div class="stat-label">Connected</div>
                </div>
            </div>
            <div class="col-4">
                <div class="stat-card">
                    <div class="stat-value text-success" id="statActions">0</div>
                    <div class="stat-label">Actions Run</div>
                </div>
            </div>
            <div class="col-4">
                <div class="stat-card">
                    <div class="stat-value text-warning" id="statUptime">0m</div>
                    <div class="stat-label">Uptime</div>
                </div>
            </div>
        </div>

        <div class="row g-4">
            <!-- QR Code Card -->
            <div class="col-md-5">
                <div class="card h-100">
                    <div class="card-header d-flex align-items-center py-3">
                        <i class="bi bi-qr-code text-info me-2"></i>
                        <span class="fw-semibold">Pair Phone</span>
                    </div>
                    <div class="card-body text-center py-4">
                        <div class="qr-container mb-3">
                            <img src="data:image/png;base64,{qr_b64}" width="200" height="200" alt="QR Code">
                        </div>
                        <p class="text-secondary small mb-1">Scan with NFCC app to connect</p>
                        <code class="text-info">{ip}:{port}</code>
                    </div>
                </div>
            </div>

            <!-- Action Log Card -->
            <div class="col-md-7">
                <div class="card h-100">
                    <div class="card-header d-flex align-items-center py-3">
                        <i class="bi bi-lightning-charge text-warning me-2"></i>
                        <span class="fw-semibold">Action Log</span>
                        <i class="bi bi-arrow-clockwise ms-auto text-secondary refresh-btn" onclick="loadData()"></i>
                    </div>
                    <div class="card-body p-0">
                        <div class="action-list" id="actionLog">
                            <div class="text-center text-secondary py-5">
                                <i class="bi bi-inbox fs-1 d-block mb-2"></i>
                                No actions yet
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- Available Actions -->
        <div class="card mt-4">
            <div class="card-header d-flex align-items-center py-3">
                <i class="bi bi-grid-3x3-gap text-success me-2"></i>
                <span class="fw-semibold">Available PC Actions</span>
            </div>
            <div class="card-body">
                <h6 class="text-secondary small mb-2">Window</h6>
                <div class="row g-2 mb-3">
                    <div class="col-6 col-md-3"><div class="d-flex align-items-center p-2 rounded" style="background:#161B22"><i class="bi bi-arrows-collapse me-2" style="color:#8B5CF6"></i><small>Minimize All</small></div></div>
                    <div class="col-6 col-md-3"><div class="d-flex align-items-center p-2 rounded" style="background:#161B22"><i class="bi bi-arrows-fullscreen me-2" style="color:#8B5CF6"></i><small>Maximize</small></div></div>
                    <div class="col-6 col-md-3"><div class="d-flex align-items-center p-2 rounded" style="background:#161B22"><i class="bi bi-layout-sidebar me-2" style="color:#8B5CF6"></i><small>Snap Left/Right</small></div></div>
                    <div class="col-6 col-md-3"><div class="d-flex align-items-center p-2 rounded" style="background:#161B22"><i class="bi bi-x-circle text-danger me-2"></i><small>Close Window</small></div></div>
                </div>
                <h6 class="text-secondary small mb-2">Sound & Media</h6>
                <div class="row g-2 mb-3">
                    <div class="col-6 col-md-3"><div class="d-flex align-items-center p-2 rounded" style="background:#161B22"><i class="bi bi-volume-mute me-2" style="color:#EC4899"></i><small>Mute/Unmute</small></div></div>
                    <div class="col-6 col-md-3"><div class="d-flex align-items-center p-2 rounded" style="background:#161B22"><i class="bi bi-volume-up text-warning me-2"></i><small>Volume +/-</small></div></div>
                    <div class="col-6 col-md-3"><div class="d-flex align-items-center p-2 rounded" style="background:#161B22"><i class="bi bi-play-circle text-info me-2"></i><small>Play/Pause</small></div></div>
                    <div class="col-6 col-md-3"><div class="d-flex align-items-center p-2 rounded" style="background:#161B22"><i class="bi bi-skip-forward text-info me-2"></i><small>Next/Prev</small></div></div>
                </div>
                <h6 class="text-secondary small mb-2">System</h6>
                <div class="row g-2 mb-3">
                    <div class="col-6 col-md-3"><div class="d-flex align-items-center p-2 rounded" style="background:#161B22"><i class="bi bi-lock text-warning me-2"></i><small>Lock PC</small></div></div>
                    <div class="col-6 col-md-3"><div class="d-flex align-items-center p-2 rounded" style="background:#161B22"><i class="bi bi-moon text-info me-2"></i><small>Sleep</small></div></div>
                    <div class="col-6 col-md-3"><div class="d-flex align-items-center p-2 rounded" style="background:#161B22"><i class="bi bi-arrow-repeat text-warning me-2"></i><small>Restart</small></div></div>
                    <div class="col-6 col-md-3"><div class="d-flex align-items-center p-2 rounded" style="background:#161B22"><i class="bi bi-power text-danger me-2"></i><small>Shutdown</small></div></div>
                </div>
                <h6 class="text-secondary small mb-2">Shortcuts</h6>
                <div class="row g-2 mb-3">
                    <div class="col-6 col-md-3"><div class="d-flex align-items-center p-2 rounded" style="background:#161B22"><i class="bi bi-camera text-info me-2"></i><small>Screenshot</small></div></div>
                    <div class="col-6 col-md-3"><div class="d-flex align-items-center p-2 rounded" style="background:#161B22"><i class="bi bi-folder text-warning me-2"></i><small>File Explorer</small></div></div>
                    <div class="col-6 col-md-3"><div class="d-flex align-items-center p-2 rounded" style="background:#161B22"><i class="bi bi-activity text-danger me-2"></i><small>Task Manager</small></div></div>
                    <div class="col-6 col-md-3"><div class="d-flex align-items-center p-2 rounded" style="background:#161B22"><i class="bi bi-display text-secondary me-2"></i><small>Screen On/Off</small></div></div>
                </div>
                <h6 class="text-secondary small mb-2">Apps & Commands</h6>
                <div class="row g-2">
                    <div class="col-6 col-md-3"><div class="d-flex align-items-center p-2 rounded" style="background:#161B22"><i class="bi bi-app-indicator text-primary me-2"></i><small>Launch App</small></div></div>
                    <div class="col-6 col-md-3"><div class="d-flex align-items-center p-2 rounded" style="background:#161B22"><i class="bi bi-globe text-info me-2"></i><small>Open URL</small></div></div>
                    <div class="col-6 col-md-3"><div class="d-flex align-items-center p-2 rounded" style="background:#161B22"><i class="bi bi-terminal text-warning me-2"></i><small>Run Command</small></div></div>
                    <div class="col-6 col-md-3"><div class="d-flex align-items-center p-2 rounded" style="background:#161B22"><i class="bi bi-x-circle text-danger me-2"></i><small>Close App</small></div></div>
                </div>
            </div>
        </div>

        <!-- App Scanner -->
        <div class="card mt-4">
            <div class="card-header d-flex align-items-center py-3">
                <i class="bi bi-search text-info me-2"></i>
                <span class="fw-semibold">App Scanner</span>
                <small class="text-secondary ms-2">find installed apps + pin them to phone packages</small>
                <div class="ms-auto d-flex gap-2">
                    <button class="btn btn-sm btn-outline-secondary" onclick="rescanApps()" type="button">
                        <i class="bi bi-arrow-repeat"></i> Rescan
                    </button>
                </div>
            </div>
            <div class="card-body">
                <p class="text-secondary small mb-2">
                    Scans Start Menu, App Paths registry, Scoop, Chocolatey,
                    per-user Programs, and Microsoft Store shims. Smart Switch
                    consults this list when the phone hands off an app the
                    static aliases don't cover (AnyDesk, Figma, Obsidian, …).
                </p>
                <div class="d-flex gap-2 align-items-center mb-2">
                    <input id="appSearchInput" class="form-control form-control-sm bg-dark text-light"
                        placeholder="Search by name (e.g. anydesk, figma, vscode)…"
                        oninput="renderApps()" style="border-color:#30363D"/>
                    <span id="appCount" class="text-secondary small" style="white-space:nowrap"></span>
                </div>
                <div id="appList" class="action-list" style="max-height:300px"></div>

                <hr style="border-color:#21262D; margin:16px 0"/>
                <div class="small text-secondary mb-2"><i class="bi bi-plus-circle me-1"></i> Add a portable / unlisted .exe</div>
                <div class="d-flex gap-2">
                    <input id="manualAppName" class="form-control form-control-sm bg-dark text-light"
                        placeholder="Display name (e.g. AnyDesk)" style="border-color:#30363D; max-width:220px"/>
                    <input id="manualAppPath" class="form-control form-control-sm bg-dark text-light"
                        placeholder="Full path to .exe (e.g. C:\\Program Files\\AnyDesk\\AnyDesk.exe)"
                        style="border-color:#30363D"/>
                    <button class="btn btn-sm btn-info" onclick="addManualApp()" type="button">Add</button>
                </div>
                <div id="appStatus" class="small mt-2" style="min-height:1.1em"></div>
            </div>
        </div>

        <!-- Smart Switch Mappings -->
        <div class="card mt-4">
            <div class="card-header d-flex align-items-center py-3">
                <i class="bi bi-arrow-left-right text-info me-2"></i>
                <span class="fw-semibold">Smart Switch Mappings</span>
                <small class="text-secondary ms-2">phone-app → PC action</small>
                <div class="ms-auto d-flex gap-2">
                    <button class="btn btn-sm btn-outline-secondary" onclick="resetMappings()" type="button">
                        <i class="bi bi-arrow-counterclockwise"></i> Reset to defaults
                    </button>
                    <button class="btn btn-sm btn-info" onclick="saveMappings()" type="button">
                        <i class="bi bi-save"></i> Save
                    </button>
                </div>
            </div>
            <div class="card-body">
                <p class="text-secondary small mb-2">
                    Edit the JSON below to override how Smart Switch handles a phone
                    app or kind. <code>by_package</code> entries win over
                    <code>by_kind</code>. Strategies: <code>url</code>,
                    <code>static_url</code>, <code>desktop_uri</code>,
                    <code>desktop_uri_then_url</code>, <code>url_or_launch</code>,
                    <code>launch_app</code>, <code>whatsapp_paste</code>.
                    Browsers: <code>default</code>, <code>chrome</code>,
                    <code>edge</code>, <code>firefox</code>, <code>brave</code>.
                </p>
                <div id="mappingStatus" class="small mb-2" style="min-height:1.1em"></div>
                <textarea id="mappingsEditor"
                    class="form-control bg-dark text-light"
                    style="font-family:'Cascadia Code', Consolas, monospace; font-size:12px; min-height:280px; border-color:#30363D"
                    spellcheck="false"></textarea>
                <details class="mt-3">
                    <summary class="text-secondary small" style="cursor:pointer">
                        Defaults (read-only reference)
                    </summary>
                    <pre id="mappingDefaults" class="mt-2 p-3 small"
                        style="background:#0D1117; border:1px solid #21262D; border-radius:8px; max-height:240px; overflow:auto"></pre>
                </details>
            </div>
        </div>

        <p class="text-center text-secondary small mt-4">
            <i class="bi bi-shield-check me-1"></i> All communication is local network only &bull; No cloud
        </p>
    </div>

    <script>
        const startTime = Date.now();

        function loadData() {{
            fetch('/api/status')
                .then(r => r.json())
                .then(data => {{
                    // Status
                    const dot = document.getElementById('statusDot');
                    const txt = document.getElementById('statusText');
                    const hasDevices = data.devices > 0;
                    dot.className = 'status-dot ' + (hasDevices ? 'online' : 'offline');
                    txt.textContent = data.status;
                    txt.className = hasDevices ? 'text-success' : 'text-secondary';

                    // Stats
                    document.getElementById('statDevices').textContent = data.devices;
                    document.getElementById('statActions').textContent = data.action_count;

                    // Uptime
                    const mins = Math.floor((Date.now() - startTime) / 60000);
                    document.getElementById('statUptime').textContent =
                        mins < 60 ? mins + 'm' : Math.floor(mins/60) + 'h ' + (mins%60) + 'm';

                    // Action log
                    const log = document.getElementById('actionLog');
                    if (data.actions.length === 0) {{
                        log.innerHTML = '<div class="text-center text-secondary py-5"><i class="bi bi-inbox fs-1 d-block mb-2"></i>No actions yet</div>';
                    }} else {{
                        log.innerHTML = data.actions.map(a => `
                            <div class="action-item d-flex align-items-center">
                                <span class="badge ${{a.success ? 'badge-success' : 'badge-fail'}} me-2">
                                    <i class="bi bi-${{a.success ? 'check-lg' : 'x-lg'}}"></i>
                                </span>
                                <div class="flex-grow-1">
                                    <div class="small fw-medium">${{a.action}}</div>
                                    <div class="text-secondary" style="font-size:0.7rem">${{a.detail}}</div>
                                </div>
                                <small class="text-secondary">${{a.time}}</small>
                            </div>
                        `).join('');
                    }}
                }})
                .catch(() => {{}});
        }}

        loadData();
        setInterval(loadData, 2000);

        // ── Smart Switch Mappings ────────────────────────────────────────
        function setMappingStatus(text, kind) {{
            const el = document.getElementById('mappingStatus');
            el.textContent = text || '';
            el.className = 'small mb-2 ' + (
                kind === 'ok' ? 'text-success' :
                kind === 'err' ? 'text-danger' : 'text-secondary');
        }}

        function loadMappings() {{
            fetch('/api/mappings')
                .then(r => r.json())
                .then(data => {{
                    const editor = document.getElementById('mappingsEditor');
                    // Show user overrides if any, else seed with effective
                    // (defaults) so the user can edit in place.
                    const seed = (data.user && Object.keys(data.user).length)
                        ? data.user
                        : data.effective;
                    editor.value = JSON.stringify(seed, null, 2);
                    document.getElementById('mappingDefaults').textContent =
                        JSON.stringify(data.defaults, null, 2);
                    setMappingStatus('', 'info');
                }})
                .catch(e => setMappingStatus('Load failed: ' + e, 'err'));
        }}

        function saveMappings() {{
            const text = document.getElementById('mappingsEditor').value;
            let parsed;
            try {{ parsed = JSON.parse(text); }}
            catch (e) {{ setMappingStatus('Invalid JSON: ' + e.message, 'err'); return; }}
            setMappingStatus('Saving…', 'info');
            fetch('/api/mappings', {{
                method: 'POST',
                headers: {{ 'Content-Type': 'application/json' }},
                body: JSON.stringify(parsed)
            }})
                .then(r => r.json())
                .then(data => {{
                    if (data.ok) setMappingStatus('Saved.', 'ok');
                    else setMappingStatus('Save failed: ' + (data.error || 'unknown'), 'err');
                }})
                .catch(e => setMappingStatus('Save failed: ' + e, 'err'));
        }}

        function resetMappings() {{
            if (!confirm('Reset Smart Switch mappings to defaults? Your overrides will be deleted.')) return;
            fetch('/api/mappings/reset', {{ method: 'POST' }})
                .then(r => r.json())
                .then(data => {{
                    if (data.ok) {{
                        setMappingStatus('Reset to defaults.', 'ok');
                        loadMappings();
                    }} else {{
                        setMappingStatus('Reset failed: ' + (data.error || 'unknown'), 'err');
                    }}
                }})
                .catch(e => setMappingStatus('Reset failed: ' + e, 'err'));
        }}

        loadMappings();

        // ── App Scanner ──────────────────────────────────────────────────
        let _allApps = [];

        function setAppStatus(text, kind) {{
            const el = document.getElementById('appStatus');
            el.textContent = text || '';
            el.className = 'small mt-2 ' + (
                kind === 'ok' ? 'text-success' :
                kind === 'err' ? 'text-danger' : 'text-secondary');
        }}

        function loadApps() {{
            fetch('/api/installed_apps')
                .then(r => r.json())
                .then(data => {{
                    if (!data.ok) {{ setAppStatus(data.error || 'load failed', 'err'); return; }}
                    const apps = (data.manual || []).concat(data.apps || []);
                    _allApps = apps;
                    if (apps.length === 0) {{
                        setAppStatus('No apps cached yet. Click Rescan.', 'info');
                    }} else {{
                        const dt = data.scannedAt ? new Date(data.scannedAt * 1000).toLocaleString() : 'never';
                        setAppStatus('Last scan: ' + dt, 'info');
                    }}
                    renderApps();
                }})
                .catch(e => setAppStatus('Load failed: ' + e, 'err'));
        }}

        function renderApps() {{
            const q = (document.getElementById('appSearchInput').value || '').toLowerCase();
            const list = document.getElementById('appList');
            const filtered = !q ? _allApps : _allApps.filter(a =>
                (a.name || '').toLowerCase().includes(q) ||
                (a.path || '').toLowerCase().includes(q));
            document.getElementById('appCount').textContent =
                filtered.length + ' / ' + _allApps.length;
            if (filtered.length === 0) {{
                list.innerHTML = '<div class="text-center text-secondary py-3 small">No matches</div>';
                return;
            }}
            // Cap to 200 rows for perf — search narrows further.
            list.innerHTML = filtered.slice(0, 200).map(a => `
                <div class="action-item d-flex align-items-center" style="gap:10px">
                    <div class="flex-grow-1" style="min-width:0">
                        <div class="small fw-medium">${{escapeHtml(a.name || '')}}</div>
                        <div class="text-secondary" style="font-size:0.7rem; word-break:break-all">${{escapeHtml(a.path || '')}}</div>
                    </div>
                    <span class="badge badge-info">${{escapeHtml(a.source || '')}}</span>
                    <button class="btn btn-sm btn-outline-info" onclick="pinAppPrompt(${{JSON.stringify(a.path || '').replace(/"/g, '&quot;')}})" type="button">
                        <i class="bi bi-link-45deg"></i> Map
                    </button>
                    ${{a.source === 'Manual' ? `<button class="btn btn-sm btn-outline-danger" onclick="removeManualApp(${{JSON.stringify(a.path).replace(/"/g, '&quot;')}})" type="button"><i class="bi bi-x"></i></button>` : ''}}
                </div>
            `).join('');
        }}

        function escapeHtml(s) {{
            return String(s).replace(/[&<>"']/g, c => ({{
                '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
            }}[c]));
        }}

        function rescanApps() {{
            setAppStatus('Scanning…', 'info');
            fetch('/api/installed_apps/scan', {{ method: 'POST' }})
                .then(r => r.json())
                .then(data => {{
                    if (!data.ok) {{ setAppStatus('Scan failed: ' + (data.error || 'unknown'), 'err'); return; }}
                    _allApps = (data.manual || []).concat(data.apps || []);
                    renderApps();
                    setAppStatus('Found ' + (data.apps || []).length + ' apps.', 'ok');
                }})
                .catch(e => setAppStatus('Scan failed: ' + e, 'err'));
        }}

        function addManualApp() {{
            const name = document.getElementById('manualAppName').value.trim();
            const path = document.getElementById('manualAppPath').value.trim();
            if (!name || !path) {{ setAppStatus('Name + path required', 'err'); return; }}
            fetch('/api/installed_apps/manual', {{
                method: 'POST',
                headers: {{ 'Content-Type': 'application/json' }},
                body: JSON.stringify({{ name, path }}),
            }})
                .then(r => r.json())
                .then(data => {{
                    if (!data.ok) {{ setAppStatus('Add failed: ' + (data.error || 'unknown'), 'err'); return; }}
                    document.getElementById('manualAppName').value = '';
                    document.getElementById('manualAppPath').value = '';
                    _allApps = (data.manual || []).concat(data.apps || []);
                    renderApps();
                    setAppStatus('Added.', 'ok');
                }})
                .catch(e => setAppStatus('Add failed: ' + e, 'err'));
        }}

        function removeManualApp(path) {{
            fetch('/api/installed_apps/manual/remove', {{
                method: 'POST',
                headers: {{ 'Content-Type': 'application/json' }},
                body: JSON.stringify({{ path }}),
            }})
                .then(r => r.json())
                .then(data => {{
                    if (!data.ok) {{ setAppStatus('Remove failed: ' + (data.error || 'unknown'), 'err'); return; }}
                    _allApps = (data.manual || []).concat(data.apps || []);
                    renderApps();
                    setAppStatus('Removed.', 'ok');
                }})
                .catch(e => setAppStatus('Remove failed: ' + e, 'err'));
        }}

        function pinAppPrompt(path) {{
            const pkg = prompt(
                'Map this PC app to which Android package?\\n\\n' +
                'Open the action log on the dashboard, copy the appPkg from a recent failed Smart Switch entry — e.g. com.anydesk.anydeskandroid — and paste it here.',
                ''
            );
            if (!pkg) return;
            fetch('/api/installed_apps/map_package', {{
                method: 'POST',
                headers: {{ 'Content-Type': 'application/json' }},
                body: JSON.stringify({{ appPkg: pkg.trim(), path }}),
            }})
                .then(r => r.json())
                .then(data => {{
                    if (!data.ok) {{ setAppStatus('Pin failed: ' + (data.error || 'unknown'), 'err'); return; }}
                    setAppStatus('Pinned ' + pkg.trim() + ' → ' + path.split(/[\\\\/]/).pop(), 'ok');
                    loadMappings();  // refresh mappings panel so the new entry shows
                }})
                .catch(e => setAppStatus('Pin failed: ' + e, 'err'));
        }}

        loadApps();
    </script>
</body>
</html>"""


class DashboardHandler(BaseHTTPRequestHandler):
    config = {}
    on_reconnect = None   # set by start_dashboard
    on_forward = None     # set by start_dashboard

    def _write_json(self, code: int, data: dict) -> None:
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_GET(self):
        if self.path == '/api/status':
            state = get_state()
            self._write_json(200, {
                "status": state.status,
                "devices": len(state.connected_devices),
                "actions": state.action_log,
                "action_count": len(state.action_log),
            })
        elif self.path == '/api/mappings':
            self._write_json(200, {
                "ok": True,
                "defaults": mappings.DEFAULT_MAPPINGS,
                "user": mappings.get_user_mappings(),
                "effective": mappings.get_effective_mappings(),
            })
        elif self.path == '/api/installed_apps':
            try:
                self._write_json(200, {
                    "ok": True,
                    **installed_apps._read_cache(),
                })
            except Exception as e:
                self._write_json(500, {"ok": False, "error": str(e)})
        else:
            html = build_html(self.config)
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            self.wfile.write(html.encode())

    def do_POST(self):
        if self.path == '/api/reconnect':
            cb = type(self).on_reconnect
            if cb is None:
                self._write_json(503, {"ok": False, "error": "reconnect not wired"})
                return
            try:
                cb()
                self._write_json(200, {"ok": True})
            except Exception as e:
                self._write_json(500, {"ok": False, "error": str(e)})
        elif self.path == '/api/forward':
            cb = type(self).on_forward
            if cb is None:
                self._write_json(503, {"ok": False, "error": "forward not wired"})
                return
            try:
                result = cb()
                self._write_json(200, {"ok": True, **(result or {})})
            except Exception as e:
                self._write_json(500, {"ok": False, "error": str(e)})
        elif self.path == '/api/mappings':
            try:
                length = int(self.headers.get('Content-Length') or 0)
                body = self.rfile.read(length) if length else b''
                data = json.loads(body.decode() or '{}')
                if not isinstance(data, dict):
                    raise ValueError("mappings body must be a JSON object")
                # Only persist the two known buckets — guards against the
                # user pasting unrelated junk into the editor.
                clean = {
                    "by_kind": data.get("by_kind") or {},
                    "by_package": data.get("by_package") or {},
                }
                mappings.save_mappings(clean)
                self._write_json(200, {"ok": True,
                                       "effective": mappings.get_effective_mappings()})
            except Exception as e:
                self._write_json(400, {"ok": False, "error": str(e)})
        elif self.path == '/api/mappings/reset':
            try:
                mappings.reset_mappings()
                self._write_json(200, {"ok": True,
                                       "effective": mappings.get_effective_mappings()})
            except Exception as e:
                self._write_json(500, {"ok": False, "error": str(e)})
        elif self.path == '/api/installed_apps/scan':
            try:
                fresh = installed_apps.rescan()
                self._write_json(200, {"ok": True, **fresh})
            except Exception as e:
                self._write_json(500, {"ok": False, "error": str(e)})
        elif self.path == '/api/installed_apps/manual':
            try:
                length = int(self.headers.get('Content-Length') or 0)
                body = self.rfile.read(length) if length else b''
                data = json.loads(body.decode() or '{}')
                cache = installed_apps.add_manual(
                    data.get("name", ""), data.get("path", "")
                )
                self._write_json(200, {"ok": True, **cache})
            except Exception as e:
                self._write_json(400, {"ok": False, "error": str(e)})
        elif self.path == '/api/installed_apps/manual/remove':
            try:
                length = int(self.headers.get('Content-Length') or 0)
                body = self.rfile.read(length) if length else b''
                data = json.loads(body.decode() or '{}')
                cache = installed_apps.remove_manual(data.get("path", ""))
                self._write_json(200, {"ok": True, **cache})
            except Exception as e:
                self._write_json(400, {"ok": False, "error": str(e)})
        elif self.path == '/api/installed_apps/map_package':
            # Pin a phone Android package to a specific PC .exe path —
            # writes a `by_package` entry into mappings.json with the
            # launch_app strategy + app_path field.
            try:
                length = int(self.headers.get('Content-Length') or 0)
                body = self.rfile.read(length) if length else b''
                data = json.loads(body.decode() or '{}')
                pkg = (data.get("appPkg") or "").strip()
                path = (data.get("path") or "").strip()
                if not pkg or not path:
                    raise ValueError("appPkg and path required")
                user = mappings.get_user_mappings()
                user.setdefault("by_package", {})
                user["by_package"][pkg] = {
                    "strategy": "launch_app",
                    "app_path": path,
                }
                mappings.save_mappings(user)
                self._write_json(200, {"ok": True,
                                       "effective": mappings.get_effective_mappings()})
            except Exception as e:
                self._write_json(400, {"ok": False, "error": str(e)})
        else:
            self._write_json(404, {"ok": False, "error": "not found"})

    def log_message(self, format, *args):
        pass  # Suppress HTTP logs


def start_dashboard(
    config: dict,
    port: int = 8877,
    *,
    on_reconnect=None,
    on_forward=None,
):
    DashboardHandler.config = config
    DashboardHandler.on_reconnect = on_reconnect
    DashboardHandler.on_forward = on_forward
    server = HTTPServer(('0.0.0.0', port), DashboardHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server


def open_dashboard(port: int = 8877):
    webbrowser.open(f"http://localhost:{port}")
