const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
const fs = require('fs');
const path = require('path');
const https = require('https');
const http = require('http');
const { exec } = require('child_process');

puppeteer.use(StealthPlugin());

// --- CONFIGURACIÓN ---
const MY_HWID = process.argv[2] || "HWID_MANUAL_DEBUG";
const API_HOST = "og-tech-backend.onrender.com";
const LOCAL_COMMAND_PORT = 4000;

// UMBRAL DE ENERGÍA REAL
const ENERGY_THRESHOLD = 20;

// Rutas absolutas
const TIMERS_FILE = path.join(__dirname, 'active_timers.json');
const TRIGGER_FILE = path.join(__dirname, 'trigger_skip.txt');
const ENERGY_FILE = path.join(__dirname, 'low_energy.txt');

// --- TIEMPOS REALES ---
const TIEMPOS = {
    "Arbol": { min: 6.00, max: 6.10 },
    "Roca": { min: 3.00, max: 3.10 },
    "Barrel": { min: 144.98, max: 145.10 },
    "Mill": { min: 11.98, max: 12.02 }
};

let MEMORY_TIMERS = [];
let ZOMBIE_LIST = {};
let CACHED_AUTH_TOKEN = null;

// Log desactivado
// Log desactivado
function log(msg) { console.log(msg); }

// Inicialización
if (fs.existsSync(TIMERS_FILE)) { try { MEMORY_TIMERS = JSON.parse(fs.readFileSync(TIMERS_FILE, 'utf8')); } catch (e) { MEMORY_TIMERS = []; } } else { fs.writeFileSync(TIMERS_FILE, '[]'); }
function guardarDisco() { try { fs.writeFileSync(TIMERS_FILE, JSON.stringify(MEMORY_TIMERS, null, 2)); } catch (e) { } }

// Helper Peticiones Node (Backend)
function nodeRequest(url, token) {
    return new Promise((resolve, reject) => {
        const options = {
            method: 'GET',
            headers: {
                'Authorization': token,
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Cache-Control': 'no-cache'
            }
        };
        const req = https.request(url, options, (res) => {
            let body = '';
            res.on('data', (chunk) => body += chunk);
            res.on('end', () => {
                try { resolve(JSON.parse(body)); } catch (e) { reject(e); }
            });
        });
        req.on('error', (e) => reject(e));
        req.end();
    });
}

function nodePostRequest(url, token, dataObj) {
    return new Promise((resolve, reject) => {
        const data = JSON.stringify(dataObj);
        const options = {
            method: 'POST',
            headers: {
                'Authorization': token,
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(data),
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
            }
        };
        const req = https.request(url, options, (res) => {
            let body = '';
            res.on('data', (chunk) => body += chunk);
            res.on('end', () => {
                try { resolve(JSON.parse(body)); } catch (e) { reject(e); }
            });
        });
        req.on('error', (e) => reject(e));
        req.write(data);
        req.end();
    });
}

function uploadToCloud(timer) {
    try {
        const data = JSON.stringify({ hwid: MY_HWID, name: timer.name, type: timer.type, id: timer.id, finBase: timer.finBase });
        const options = { hostname: API_HOST, path: '/api/sync_timer', method: 'POST', headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) } };
        const req = https.request(options, (res) => { });
        req.on('error', (e) => { });
        req.write(data);
        req.end();
    } catch (e) { }
}

setInterval(() => {
    const now = Date.now();
    let huboCambios = false;
    const cantidadAntes = MEMORY_TIMERS.length;
    MEMORY_TIMERS = MEMORY_TIMERS.filter(t => now < (t.finMax + 3000));
    if (MEMORY_TIMERS.length !== cantidadAntes) huboCambios = true;
    if (huboCambios) guardarDisco();
}, 1000);

function updateDatabase(newTimer, mostrarEnHud) {
    const now = Date.now();
    const uniqueId = newTimer.objectId ? (newTimer.id + "_" + newTimer.objectId) : (newTimer.id + "_" + newTimer.finBase);
    uploadToCloud(newTimer);
    if (!mostrarEnHud) {
        const index = MEMORY_TIMERS.findIndex(t => t.id === newTimer.id && t.type === newTimer.type);
        if (index !== -1) { MEMORY_TIMERS[index] = newTimer; guardarDisco(); }
        return;
    }
    if (ZOMBIE_LIST[uniqueId] && (now - ZOMBIE_LIST[uniqueId] < 45000)) return;
    MEMORY_TIMERS = MEMORY_TIMERS.filter(t => t.finMax > (now - 25200000));
    const index = MEMORY_TIMERS.findIndex(t => {
        if (newTimer.objectId && t.objectId) return t.objectId === newTimer.objectId;
        return t.id === newTimer.id && t.type === newTimer.type;
    });
    if (index === -1) { MEMORY_TIMERS.push(newTimer); }
    else {
        const existing = MEMORY_TIMERS[index];
        if (Math.abs(existing.finBase - newTimer.finBase) > 60000) MEMORY_TIMERS[index] = newTimer;
    }
    MEMORY_TIMERS.sort((a, b) => a.finBase - b.finBase);
    guardarDisco();
}

function procesarEdificio(landId, objeto, esInteraccionActiva) {
    if (!objeto.data || !objeto.data.batch || !objeto.data.batch.startedAt) return;
    const startedAt = new Date(objeto.data.batch.startedAt).getTime();
    let configTiempo = null; let nombre = "Edificio";
    if (objeto.slug === 'barrel') { nombre = "🛢️ Barrel"; configTiempo = TIEMPOS.Barrel; }
    else if (objeto.slug === 'mill') { nombre = "🌬️ Mill"; configTiempo = TIEMPOS.Mill; }
    else { return; }
    const finBase = startedAt + (configTiempo.min * 3600000);
    const finMax = startedAt + (configTiempo.max * 3600000);
    if (finBase > (Date.now() - 86400000)) {
        updateDatabase({ name: nombre, type: "Construccion", finBase: finBase, finMax: finMax, url: `https://nomstead.com/u/${landId}`, id: landId, objectId: objeto._id }, esInteraccionActiva);
    }
}
const NOTIFY_FILE = path.join(__dirname, 'latest_action.txt');
let ACTION_QUEUE = [];
let IS_PROCESSING_QUEUE = false;
let CURRENT_LAND_OBJECTS = []; // Persistencia de objetos en la land actual

// Loop de "Refill" para mantener la accion constante sobre los objetos visibles
setInterval(() => {
    // Si la cola se vacía pero seguimos teniendo objetos en la mira, recargamos la cola
    if (ACTION_QUEUE.length === 0 && CURRENT_LAND_OBJECTS.length > 0) {
        // Agregamos todos los de la land actual para re-probar suerte
        CURRENT_LAND_OBJECTS.forEach(item => addToQueue(item));
    }
}, 2000); // Chequea cada 2s si la cola se vació

function addToQueue(actionItem) {
    // 1. Eliminado el PROCESSED_IDS (cache de 5 min) para permitir reintentos constantes
    // if (PROCESSED_IDS[actionItem.uniqueId]...) // BORRADO

    // 2. Solo evitamos duplicados SI YA ESTA esperando en la cola actual
    const exists = ACTION_QUEUE.find(a => a.uniqueId === actionItem.uniqueId);
    if (exists) return;

    ACTION_QUEUE.push(actionItem);
    processQueue();
}

async function processQueue() {
    if (IS_PROCESSING_QUEUE) return;
    if (ACTION_QUEUE.length === 0) return;

    IS_PROCESSING_QUEUE = true;

    while (ACTION_QUEUE.length > 0) {
        if (!CACHED_AUTH_TOKEN) { // Esperar si no hay token
            await new Promise(r => setTimeout(r, 1000));
            continue;
        }

        const item = ACTION_QUEUE[0]; // Peek

        // Ejecutar Acción
        try {
            const apiRes = await nodePostRequest(item.url, CACHED_AUTH_TOKEN, { path: `${item.landId}/${item.id}` });

            // Logica Anti-Spam (Definitiva): Verificar propiedad "quantity"
            let success = false;

            if (apiRes && !apiRes.error) {
                // El usuario confirmó que el éxito viene marcado por "quantity" (ej: "quantity": 3)
                if (apiRes.quantity !== undefined && apiRes.quantity > 0) {
                    success = true;
                    log(`[QUEUE] ✅ RECOLECCIÓN REALIZADA (Loot: ${apiRes.quantity}): ${item.type} ${item.id}`);
                } else {
                    // Si dice "already chopped" o no trae quantity, es fallo/ignoramos
                    const msg = apiRes.message || JSON.stringify(apiRes);
                    log(`[QUEUE] ⚠️ Sin loot (ya cortado/ocupado): ${msg.substring(0, 100)}`);
                }
            } else {
                log(`[QUEUE] ❌ Error API o respuesta vacía`);
            }

            if (success) {
                // Éxito
                const now = Date.now();
                const displayName = (item.type === "Arbol") ? "🌲 Tree" : "🪨 Rock";

                // 1. Update DB Local
                updateDatabase({
                    name: displayName, type: item.type,
                    finBase: now + (item.timeConfig.min * 3600000), finMax: now + (item.timeConfig.max * 3600000),
                    url: `https://nomstead.com/u/${item.landId}`, id: item.landId, objectId: item.id
                }, true);

                // 2. Comunicar a AHK (Visual Notify)
                try {
                    fs.writeFileSync(NOTIFY_FILE, `${now}|${item.type}|${displayName} (+${apiRes.quantity})`);
                } catch (e) { }

                // PROCESSED_IDS[item.uniqueId] = now; // YA NO SE USA, QUEREMOS RE-INTENTAR
            }

        } catch (err) {
            // Error de red, ignoramos
        }

        // Remover de la cola y esperar delay rapido de 800ms
        ACTION_QUEUE.shift();
        const humanDelay = 100; // Constante rapida solicitada
        await new Promise(r => setTimeout(r, humanDelay));
    }

    IS_PROCESSING_QUEUE = false;
}

(async () => {
    try {
        const browser = await puppeteer.connect({ browserURL: 'http://127.0.0.1:9222', defaultViewport: null });
        const targets = await browser.targets();
        const pageTarget = targets.find(t => t.url().includes('nomstead.com'));
        if (!pageTarget) return;

        const page = await pageTarget.page();
        log("✅ Conectado a Tab de Nomstead: " + (await page.title()));

        // === AUTO-LOGIN SYSTEM ===
        async function intentarAutoLogin() {
            try {
                const currentUrl = page.url();

                // Verificar si estamos en página de login
                if (currentUrl.includes('/auth/signin') || currentUrl.includes('/signin')) {
                    log("🔐 Página de login detectada. Iniciando auto-login...");

                    // Esperar a que cargue el botón "Sign in with Immutable"
                    await page.waitForSelector('button', { timeout: 10000 });

                    // Buscar el botón por texto
                    const btnSignIn = await page.evaluateHandle(() => {
                        const buttons = document.querySelectorAll('button');
                        for (const btn of buttons) {
                            if (btn.textContent.toLowerCase().includes('immutable')) {
                                return btn;
                            }
                        }
                        return null;
                    });

                    if (btnSignIn) {
                        log("🖱️ Haciendo click en 'Sign in with Immutable'...");
                        await btnSignIn.click();

                        // Esperar a que aparezca el popup de Immutable Passport
                        log("⏳ Esperando popup de Immutable Passport...");

                        const popupTarget = await browser.waitForTarget(
                            target => target.url().includes('auth.immutable.com'),
                            { timeout: 15000 }
                        );

                        if (popupTarget) {
                            const popupPage = await popupTarget.page();
                            log("✅ Popup de Immutable detectado");

                            // Esperar a que cargue la página del popup
                            await popupPage.waitForSelector('button', { timeout: 10000 });
                            await new Promise(r => setTimeout(r, 1500)); // Pequeña espera para que cargue bien

                            // Buscar botón de Google (puede ser por aria-label, clase, o contenido)
                            const googleBtn = await popupPage.evaluateHandle(() => {
                                // Intentar por varios selectores comunes
                                const buttons = document.querySelectorAll('button');
                                for (const btn of buttons) {
                                    // Click en el primer botón de login social (generalmente Google está primero)
                                    const ariaLabel = btn.getAttribute('aria-label') || '';
                                    const text = btn.textContent.toLowerCase();
                                    if (ariaLabel.toLowerCase().includes('google') ||
                                        text.includes('google') ||
                                        btn.querySelector('svg[viewBox]')) { // Iconos SVG
                                        return btn;
                                    }
                                }
                                // Si no encontramos por texto, buscar el primer botón circular/social
                                const socialBtns = document.querySelectorAll('button[class*="social"], button[class*="oauth"], div[role="button"]');
                                if (socialBtns.length > 0) return socialBtns[0];
                                return null;
                            });

                            if (googleBtn) {
                                log("🖱️ Haciendo click en botón de Google...");
                                await googleBtn.click();
                                log("✅ Auto-login iniciado. Esperando redirección...");

                                // Esperar a que se complete el login (máximo 30 seg)
                                await new Promise(r => setTimeout(r, 5000));

                                // Verificar si el popup sigue abierto con mensaje de éxito
                                try {
                                    const allPages = await browser.pages();
                                    for (const p of allPages) {
                                        const pUrl = p.url();
                                        // Buscar popup de redirect/success de Nomstead
                                        if (pUrl.includes('nomstead.com/redirect') || pUrl.includes('auth.immutable.com')) {
                                            const bodyText = await p.evaluate(() => document.body?.innerText || '');
                                            if (bodyText.includes('logged in') || bodyText.includes('redirected')) {
                                                log("🔄 Popup de confirmación detectado. Cerrando...");
                                                await p.close();
                                                log("✅ Popup cerrado exitosamente.");
                                            }
                                        }
                                    }
                                } catch (closeErr) {
                                    log("⚠️ Error cerrando popup: " + closeErr.message);
                                }
                            } else {
                                log("⚠️ No se encontró el botón de Google. Login manual requerido.");
                            }
                        }
                    } else {
                        log("⚠️ No se encontró botón 'Sign in with Immutable'");
                    }
                }
            } catch (err) {
                log("⚠️ Auto-login error: " + err.message);
            }
        }

        // Ejecutar auto-login al inicio
        await intentarAutoLogin();

        // === MONITOREO CONTINUO DE LOGIN ===
        // Verificar cada 10 segundos si aparece la página de login (sesión expirada)
        let autoLoginEnProceso = false;
        setInterval(async () => {
            if (autoLoginEnProceso) return; // Evitar múltiples intentos simultáneos

            try {
                const currentUrl = page.url();
                if (currentUrl.includes('/auth/signin') || currentUrl.includes('/signin')) {
                    autoLoginEnProceso = true;
                    log("🔄 Sesión expirada detectada. Re-intentando auto-login...");
                    await intentarAutoLogin();
                    autoLoginEnProceso = false;
                }
            } catch (e) {
                autoLoginEnProceso = false;
            }
        }, 10000); // Cada 10 segundos

        // === MONITOREO DE POPUPS COLGADOS ===
        // Verificar cada 5 segundos si hay popups de login que quedaron abiertos
        setInterval(async () => {
            try {
                const allPages = await browser.pages();
                for (const p of allPages) {
                    try {
                        const pUrl = p.url();
                        // Detectar popup de redirect que se quedó colgado
                        if (pUrl.includes('nomstead.com/redirect') ||
                            (pUrl.includes('auth.immutable.com') && !pUrl.includes('login'))) {
                            const bodyText = await p.evaluate(() => document.body?.innerText || '');
                            if (bodyText.includes('logged in') || bodyText.includes('redirected')) {
                                log("🧹 Limpiando popup de login colgado...");
                                await p.close();
                            }
                        }
                    } catch (innerErr) {
                        // La página puede haberse cerrado, ignorar
                    }
                }
            } catch (e) {
                // Ignorar errores
            }
        }, 5000); // Cada 5 segundos

        // === COLD START FIX: INTENTAR RECUPERAR TOKEN DEL STORAGE ===
        try {
            const tokenStorage = await page.evaluate(() => {
                return localStorage.getItem('token') || localStorage.getItem('auth') || localStorage.getItem('access_token');
            });
            if (tokenStorage) {
                CACHED_AUTH_TOKEN = tokenStorage;
                log("🔑 TOKEN RECUPERADO DE STORAGE (Cold Start)");
                log("[BOT] AUTO-ACTIONS READY");
            } else {
                log("⚠️ No Token in Storage. Move character to capture net traffic.");
            }
        } catch (e) {
            log("⚠️ Error reading storage: " + e.message);
        }

        const localServer = http.createServer(async (req, res) => {
            const urlObj = new URL(req.url, `http://localhost:${LOCAL_COMMAND_PORT}`);
            if (urlObj.pathname === '/click') {
                const x = parseInt(urlObj.searchParams.get('x')); const y = parseInt(urlObj.searchParams.get('y'));
                if (!isNaN(x) && !isNaN(y)) { try { await page.mouse.click(x, y); res.writeHead(200); res.end('OK'); } catch (e) { res.writeHead(500); res.end('Error'); } }
                else { res.writeHead(400); res.end('Bad coords'); }
            }
            else if (urlObj.pathname === '/navigate') {
                const targetUrl = urlObj.searchParams.get('url');
                if (targetUrl) { try { await page.goto(targetUrl, { waitUntil: 'domcontentloaded' }); res.writeHead(200); res.end('OK'); } catch (e) { res.writeHead(500); res.end('Error Nav'); } }
                else { res.writeHead(400); res.end('No URL'); }
            }
            else { res.writeHead(404); res.end('Not found'); }
        });


        // Función para matar proceso en puerto
        const killPort = (port) => {
            return new Promise((resolve) => {
                exec(`netstat -ano | findstr :${port}`, (err, stdout) => {
                    if (err || !stdout) return resolve();

                    const lines = stdout.trim().split('\n');
                    let killed = false;

                    lines.forEach(line => {
                        const parts = line.trim().split(/\s+/);
                        const pid = parts[parts.length - 1];
                        if (pid && pid !== '0') {
                            try {
                                exec(`taskkill /F /PID ${pid}`, () => { });
                                killed = true;
                            } catch (e) { }
                        }
                    });

                    // Dar un momento para que el sistema libere el puerto
                    setTimeout(resolve, killed ? 1000 : 0);
                });
            });
        };

        // Iniciar servidor con limpieza previa
        await killPort(LOCAL_COMMAND_PORT);

        localServer.on('error', (err) => {
            if (err.code === 'EADDRINUSE') {
                log(`⚠️ Puerto ${LOCAL_COMMAND_PORT} ocupado. Reintentando en 1s...`);
                setTimeout(() => {
                    localServer.close();
                    localServer.listen(LOCAL_COMMAND_PORT);
                }, 1000);
            } else {
                log(`⚠️ Error en servidor local: ${err.message}`);
            }
        });

        localServer.listen(LOCAL_COMMAND_PORT, () => {
            log(`🌐 Servidor local escuchando en puerto ${LOCAL_COMMAND_PORT}`);
        });

        // === MONITOR DE ENERGÍA (SILENCIOSO) ===
        setInterval(async () => {
            if (!CACHED_AUTH_TOKEN) return; // Si no hay token, esperamos
            try {
                // Petición directa al servidor
                const jsonData = await nodeRequest(`https://api.nomstead.com/me?z=${Date.now()}`, CACHED_AUTH_TOKEN);

                let e = -1;
                if (jsonData.energy !== undefined) e = jsonData.energy;
                else if (jsonData.user?.energy !== undefined) e = jsonData.user.energy;

                // Chequeo de Umbral
                if (e !== -1 && e < ENERGY_THRESHOLD) {
                    try { fs.writeFileSync(ENERGY_FILE, 'LOW'); } catch (e) { }
                }
            } catch (err) { }
        }, 15000);

        page.on('response', async (response) => {
            const url = response.url();
            // A) SALTO DE TIERRA
            if (url.includes('/object/pond/fish') && response.status() === 403) {
                try { fs.writeFileSync(TRIGGER_FILE, 'SKIP'); } catch (e) { }
            }
            // B) PASIVO MAPA
            if (url.includes('/api.nomstead.com/tiles/')) {
                try {
                    const json = await response.json();
                    if (json.tile && json.tile.objects) {
                        log(`[TILES] 📍 Land detectada: ${json.tile._id} con ${json.tile.objects.length} objetos`);

                        // 0. Limpieza: Nueva land = Nuevos objetos. Limpiamos lista anterior.
                        CURRENT_LAND_OBJECTS = [];

                        let treesFound = 0, rocksFound = 0, actionableCount = 0;

                        json.tile.objects.forEach(obj => {
                            // 1. Procesamiento de Edificios (Pasivo - Timers)
                            procesarEdificio(json.tile._id, obj, false);

                            // 2. Packet Injection (Activo - Recolección)
                            if (CACHED_AUTH_TOKEN) {
                                let actionUrl = "";
                                let typeLabel = "";
                                let timeConfig = null;

                                if (obj.slug && obj.slug.includes('tree')) {
                                    actionUrl = "https://api.nomstead.com/object/tree/cut";
                                    typeLabel = "Arbol";
                                    timeConfig = TIEMPOS.Arbol;
                                    treesFound++;
                                } else if (obj.slug && obj.slug.includes('rock')) {
                                    actionUrl = "https://api.nomstead.com/object/rock/mine";
                                    typeLabel = "Roca";
                                    timeConfig = TIEMPOS.Roca;
                                    rocksFound++;
                                }

                                if (actionUrl !== "" && (!obj.data || !obj.data.batch)) {
                                    actionableCount++;
                                    const actionItem = {
                                        id: obj._id,
                                        landId: json.tile._id,
                                        url: actionUrl,
                                        type: typeLabel,
                                        timeConfig: timeConfig,
                                        uniqueId: json.tile._id + "_" + obj._id
                                    };

                                    // Agregar a lista persistente
                                    CURRENT_LAND_OBJECTS.push(actionItem);

                                    // Iniciar cola
                                    addToQueue(actionItem);
                                }
                            }
                        });

                        log(`[TILES] 🌲 Trees: ${treesFound}, 🪨 Rocks: ${rocksFound}, Accionables: ${actionableCount}`);
                        if (!CACHED_AUTH_TOKEN) {
                            log(`[TILES] ⚠️ NO HAY TOKEN - Las acciones no se ejecutarán`);
                        }
                    }
                } catch (e) { }
            }

            // C) ACTIVO EDIFICIO
            if (url.includes('/community-tool/participate')) {
                try {
                    const json = await response.json();
                    const currentUrl = page.url();
                    const urlParts = currentUrl.split('?')[0].split('/');
                    const landId = urlParts[urlParts.length - 1];
                    procesarEdificio(landId, json, true);
                } catch (e) { }
            }
        });

        page.on('request', async (request) => {
            const url = request.url();

            // CAPTURA DE TOKEN (Invisible)
            if (url.includes('api.nomstead.com') && !CACHED_AUTH_TOKEN) {
                const headers = request.headers();
                const token = headers['authorization'] || headers['Authorization'];
                if (token) {
                    CACHED_AUTH_TOKEN = token;
                    log("🔑 TOKEN CAPTURADO: " + token.substring(0, 15) + "...");
                }
            }

            if ((url.includes('/object/') || url.includes('/cut') || url.includes('/mine')) && !url.includes('community-tool')) {
                try {
                    const postData = request.postData();
                    if (!postData) return;
                    const jsonPayload = JSON.parse(postData);
                    const pathStr = jsonPayload.path;
                    if (pathStr && pathStr.includes('/')) {
                        const parts = pathStr.split('/');
                        const landID = parts[0]; const objectID = parts[1];
                        let type = "Other"; let name = "Objeto"; let timeConfig = { min: 0.01, max: 0.02 };
                        if (url.includes('tree')) { type = "Arbol"; name = "🌲 Tree"; timeConfig = TIEMPOS.Arbol; }
                        else if (url.includes('rock')) { type = "Roca"; name = "🪨 Rock"; timeConfig = TIEMPOS.Roca; }
                        if (type !== "Other") {
                            const now = Date.now();
                            updateDatabase({
                                name: name, type: type,
                                finBase: now + (timeConfig.min * 3600000), finMax: now + (timeConfig.max * 3600000),
                                url: page.url().includes(landID) ? page.url() : `https://nomstead.com/u/${landID}`,
                                id: landID, objectId: objectID
                            }, true);
                        }
                    }
                } catch (e) { }
            }
        });
        await new Promise(() => { });
    } catch (e) { process.exit(1); }
})();