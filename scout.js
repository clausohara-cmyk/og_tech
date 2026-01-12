const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
const fs = require('fs');
const path = require('path');
const https = require('https');

// Importación condicional de adm-zip para evitar fallos si no se instaló aún
let AdmZip;
try {
    AdmZip = require('adm-zip');
} catch (e) {
    // Se cargará más tarde tras el setup si es necesario
}

puppeteer.use(StealthPlugin());

// --- CONFIGURACIÓN ---
const SCOUT_EMAIL = process.argv[2] || "";
const SCOUT_PASSWORD = process.argv[3] || "";
const URL_LIST_FILE = process.argv[4] || path.join(__dirname, 'scout_urls.txt');
const DO_SHUFFLE = process.argv[5] === "1";
const IS_VISIBLE = process.argv[6] === "VISIBLE"; // Nuevo flag para debug
const USER_DATA_DIR = path.join(__dirname, 'ScoutProfile');
const FOUND_FILE = path.join(__dirname, 'found.txt');
// --- CONFIGURACIÓN DE TIEMPOS ---
// Aquí cambias cuánto tiempo espera el Scout entre cada salto de land (en milisegundos)
// 1000 = 1 segundo. Actualmente: 3.7 segundos
const SCAN_DELAY = 4500;
// ---------------------------------

function log(msg) {
    const time = new Date().toLocaleTimeString();
    const entry = `[SCOUT ${time}] ${msg}`;
    console.log(entry);
    try {
        fs.appendFileSync(path.join(__dirname, 'scout_log.txt'), entry + '\n');
    } catch (e) { }
}

async function takeDebugScreenshot(page, name) {
    if (!IS_VISIBLE) {
        try {
            const screenshotPath = path.join(__dirname, `debug_${name}.png`);
            await page.screenshot({ path: screenshotPath });
            log(`📸 Screenshot guardado: ${screenshotPath}`);
        } catch (e) {
            log(`⚠️ Error capturando screenshot: ${e.message}`);
        }
    }
}

function shuffleArray(array) {
    for (let i = array.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [array[i], array[j]] = [array[j], array[i]];
    }
}

// Cargar URLs desde archivo
function loadUrlList() {
    try {
        if (!fs.existsSync(URL_LIST_FILE)) {
            log(`⚠️ Archivo de URLs no encontrado: ${URL_LIST_FILE}`);
            return [];
        }
        const content = fs.readFileSync(URL_LIST_FILE, 'utf8');
        return content.split('\n')
            .map(line => line.trim())
            .filter(line => line && line.startsWith('http'));
    } catch (e) {
        log(`❌ Error leyendo URLs: ${e.message}`);
        return [];
    }
}

// Notificar Discord (opcional)
function notifyDiscord(landUrl, resourceType) {
    const WEBHOOK = process.env.SCOUT_WEBHOOK || "";
    if (!WEBHOOK) return;

    try {
        const data = JSON.stringify({
            username: "Scout Bot",
            embeds: [{
                title: "🎯 Recursos Detectados",
                color: 65280,
                fields: [
                    { name: "Land", value: landUrl },
                    { name: "Tipo", value: resourceType }
                ]
            }]
        });

        const url = new URL(WEBHOOK);
        const options = {
            hostname: url.hostname,
            path: url.pathname + url.search,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(data)
            }
        };

        const req = https.request(options);
        req.write(data);
        req.end();
    } catch (e) {
        // Silencio
    }
}

(async () => {
    try {
        log("🚀 Iniciando Scout Bot...");
        if (IS_VISIBLE) log("👁️ MODO VISIBLE ACTIVADO (Para login manual)");

        if (!SCOUT_EMAIL || !SCOUT_PASSWORD) {
            log("❌ Credenciales no proporcionadas. Saliendo...");
            process.exit(1);
        }

        // Cargar lista de URLs
        const urlList = loadUrlList();
        if (urlList.length === 0) {
            log("❌ No hay URLs para escanear. Saliendo...");
            process.exit(1);
        }

        log(`📋 URLs cargadas: ${urlList.length}`);
        if (DO_SHUFFLE) {
            log("🎲 Modo Aleatorio activado: Barajando lista...");
            shuffleArray(urlList);
        }

        // Función para verificar si la extensión oficial está instalada
        // Si no está, abre la tienda para que el usuario la instale (SOLO UNA VEZ)
        async function ensureVPNInstalled(browser) {
            const VPN_ID = "fhggeljlcambnphlgjbgnenndddhldkg"; // Planet VPN Lite
            const STORE_URL = "https://chromewebstore.google.com/detail/vpn-usa-planet-vpn-lite-p/fhggeljlcambnphlgjbgnenndddhldkg";

            log("🔍 Verificando instalación de Planet VPN Lite...");

            // Debug: Listar targets para ver qué detecta realmente
            let targets = await browser.targets();
            log("🔎 DEBUG: Listando todos los targets detectados:");
            targets.forEach(t => {
                log(`   > [${t.type()}] ${t.url()}`);
            });

            // IMPORTANTE: Verificar SOLO service_worker o background_page, NO páginas normales
            let isInstalled = targets.some(t =>
                (t.type() === 'service_worker' || t.type() === 'background_page') &&
                t.url().includes(VPN_ID)
            );

            if (isInstalled) {
                log("✅ VPN detectado en el perfil.");
                return true;
            }

            log("🚨 VPN no encontrado en el perfil. Iniciando asistente de instalación...");
            log("👉 Por favor, haz click en 'Añadir a Chrome' cuando veas la página.");

            const page = (await browser.pages())[0];
            await page.goto(STORE_URL, { waitUntil: 'domcontentloaded' });

            // Esperar activamente a que el usuario instale
            process.stdout.write("[SCOUT] ⏳ Esperando instalación... ");
            while (!isInstalled) {
                await new Promise(r => setTimeout(r, 1500)); // Chequear cada 1.5s

                // CHEQUEO PRECISO: Solo service_worker o background_page indican instalación real
                targets = await browser.targets();
                const extensionTarget = targets.find(t =>
                    (t.type() === 'service_worker' || t.type() === 'background_page') &&
                    t.url().includes(VPN_ID)
                );

                if (extensionTarget) {
                    isInstalled = true;
                    log(`\n✅ Extensión detectada como ${extensionTarget.type()}`);
                    break;
                }

                process.stdout.write(".");
            }
            console.log(""); // Nueva linea
            log("🎉 ¡Instalación CONFIRMADA (Service Worker detectado)!");
            log("⏳ Esperando 3 segundos para que la extensión se inicialice...");
            await new Promise(r => setTimeout(r, 3000)); // Dar tiempo suficiente

            // Cerrar la pestaña de la tienda y cualquier otra relacionada con la instalación
            log("🧹 Cerrando pestañas de instalación...");
            try {
                const allPages = await browser.pages();
                for (const p of allPages) {
                    const url = p.url().toLowerCase();
                    // Cerrar tabs de Chrome Web Store, install, y Planet VPN promo
                    if (url.includes('chromewebstore') ||
                        url.includes(VPN_ID.toLowerCase()) ||
                        url.includes('install') ||
                        url.includes('freevpn-planet') ||
                        url.includes('planetvpn')) {
                        log(`   🗑️ Cerrando: ${p.url().substring(0, 50)}...`);
                        await p.close().catch(e => { });
                    }
                }
            } catch (e) {
                log(`⚠️ Error cerrando pestañas: ${e.message}`);
            }

            return true;
        }

        const commonChromePaths = [
            'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
            'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
            path.join(process.env.LOCALAPPDATA || "", 'Google\\Chrome\\Application\\chrome.exe')
        ];

        let chromePath = undefined;
        for (const p of commonChromePaths) {
            if (fs.existsSync(p)) {
                chromePath = p;
                break;
            }
        }

        // --- SOLUCIÓN "BROWSER NOT SECURE" ---
        // En lugar de que Puppeteer inicie Chrome (lo cual setea flags de automatización),
        // iniciamos Chrome como un proceso normal con un puerto de depuración abierto.
        // Google confía más en este tipo de sesión.

        // --- NUEVO MÉTODO SOLICITADO (Manual Chrome + Puppeteer Connect) ---
        // El usuario debe haber lanzado LAUNCH_SCOUT.bat primero
        // Ese .bat abre Chrome en puerto 9223 con perfil ScoutProfile

        // --- ESTRATEGIA DUAL: CONECTAR O LANZAR ---
        log("🔍 Intentando conectar al Chrome del Scout (Puerto 9223)...");

        let browser;
        try {
            // Intentar conectar al Chrome manual (usuario usó PRE-LAUNCH)
            browser = await puppeteer.connect({
                browserURL: 'http://127.0.0.1:9223',
                defaultViewport: null
            });

            log("✅ Conectado a Chrome manual (PRE-LAUNCH).");

        } catch (connectError) {
            log("⚠️ No se encontró Chrome manual en puerto 9223.");
            log("🚀 Lanzando Chrome automáticamente con sesión guardada...");

            try {
                browser = await puppeteer.launch({
                    headless: IS_VISIBLE ? false : "new",
                    executablePath: chromePath,
                    userDataDir: USER_DATA_DIR, // ScoutProfile con sesión guardada
                    args: [
                        '--no-sandbox',
                        '--disable-setuid-sandbox',
                        '--disable-blink-features=AutomationControlled',
                        '--disable-infobars',
                        '--start-maximized',
                        '--window-position=0,0'
                    ],
                    ignoreDefaultArgs: ['--enable-automation']
                });

                log("✅ Chrome lanzado automáticamente.");
                log("📋 Si no estás logueado, usa PRE-LAUNCH una vez para guardar la sesión.");

            } catch (launchError) {
                log(`❌ ERROR: No se pudo lanzar Chrome.`);
                log(`📋 Detalles: ${launchError.message}`);
                log(`💡 Ejecuta PRE-LAUNCH primero para configurar la sesión.`);
                process.exit(1);
            }
        }

        log("✅ Conexión establecida con el navegador del Scout.");

        // --- AUTO-CONEXIÓN VPN (NUEVO) ---
        log("🛡️ Verificando estado del VPN...");
        try {
            // 1. Buscar si ya hay una pestaña de Planet VPN abierta
            const pages = await browser.pages();
            let vpnPage = pages.find(p => p.url().includes('extension') && p.url().includes('planet'));

            // 2. Si no hay, intentar abrir la página de opciones/popup (URL conocida de Planet VPN Lite)
            if (!vpnPage) {
                // ID común de Planet VPN Lite: fhggeljlcambnphlgjbgnenndddhldkg
                // Intentamos abrir su página de popup directa
                vpnPage = await browser.newPage();
                await vpnPage.goto('chrome-extension://fhggeljlcambnphlgjbgnenndddhldkg/popup.html', { waitUntil: 'domcontentloaded' }).catch(() => null);
            }

            if (vpnPage) {
                await vpnPage.bringToFront();
                try {
                    // Esperar un poco a que cargue la UI
                    await vpnPage.waitForSelector('body', { timeout: 5000 });

                    // Chequear si dice "Not protected"
                    const content = await vpnPage.content();
                    if (content.includes('Not protected')) {
                        log("⚠️ VPN Desconectado. Conectando...");

                        // Buscar el botón grande de conectar. Clase habitual: "connect-btn" o por texto
                        // Intentamos clickear por texto o selector genérico de botón grande
                        const btnClicked = await vpnPage.evaluate(() => {
                            const buttons = Array.from(document.querySelectorAll('button, div[role="button"]'));
                            const connectBtn = buttons.find(b => b.textContent.includes('Connect') || b.textContent.includes('Conectar'));
                            if (connectBtn) {
                                connectBtn.click();
                                return true;
                            }
                            return false;
                        });

                        if (btnClicked) {
                            log("✅ Click en 'Connect to VPN' enviado. Esperando conexión...");
                            await new Promise(r => setTimeout(r, 5000)); // Esperar a que conecte
                        } else {
                            log("⚠️ No se encontró el botón de conectar. ¿Ya está conectado?");
                        }
                    } else {
                        log("✅ VPN ya parece estar conectado o protegiendo.");
                    }

                    // Opcional: Cerrar la pestaña del VPN para no molestar
                    if (vpnPage) await vpnPage.close();

                } catch (vpnErr) {
                    log(`⚠️ Error interactuando con UI del VPN: ${vpnErr.message}`);
                }
            } else {
                log("⚠️ No se pudo acceder a la página del VPN. Asegúrate de tener Planet VPN instalado.");
            }

        } catch (e) {
            log(`⚠️ Verificación VPN falló (no crítico): ${e.message}`);
        }
        // ---------------------------------

        log("📋 El bot asume que YA estás logueado y el VPN YA está activado.");

        // Obtenemos la primera página disponible
        const pages = await browser.pages();
        let page = pages.find(p => p.url().includes('nomstead.com'));

        if (!page) {
            // Si no hay una página de Nomstead, usamos la primera disponible o creamos una
            page = pages.length > 0 ? pages[0] : await browser.newPage();
            log("📍 Navegando a Nomstead...");
            await page.goto('https://nomstead.com', { waitUntil: 'domcontentloaded' });
        } else {
            log("✅ Página de Nomstead ya abierta, usando esa.");
        }

        // User Agent de alta reputación
        await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');

        log("🌐 Entorno de navegación listo.");
        log("🔍 Iniciando escaneo de recursos...");

        // === AUTO-LOGIN / SESSION CHECK ===
        log("🔐 Verificando sesión...");

        await page.goto('https://nomstead.com', { waitUntil: 'domcontentloaded', timeout: 30000 });
        await new Promise(r => setTimeout(r, 6000));

        log(`📍 URL actual: ${page.url()}`);

        // Si ya estamos logueados (estamos en dashboard o land), saltamos todo
        if (page.url().includes('/dashboard') || page.url().includes('/play/')) {
            log("✅ Sesión detectada (Manual/Profile). ¡Listo para escanear!");
        } else if (page.url().includes('auth/signin') || page.url().includes('nomstead.com/')) {
            // ... resto del login automático ...
            if (page.url() === 'https://nomstead.com/') {
                log("🚀 Navegando a signin...");
                await page.goto('https://nomstead.com/auth/signin', { waitUntil: 'networkidle2' });
            }

            log("🔑 Esperando botones de login...");
            try {
                await page.waitForSelector('button', { timeout: 10000 });
                const btnSignIn = await page.evaluateHandle(() => {
                    const buttons = document.querySelectorAll('button');
                    for (const btn of buttons) {
                        const txt = btn.textContent.toLowerCase();
                        if (txt.includes('immutable') || txt.includes('sign in')) return btn;
                    }
                    return null;
                });

                if (btnSignIn && !page.url().includes('auth.immutable.com')) {
                    await btnSignIn.click();
                    log("🖱️ Click en botón de Login");
                    await new Promise(r => setTimeout(r, 10000));
                }
            } catch (e) {
                log("⚠️ No se detectaron botones (Si ya ves el dashboard, ignora esto).");
            }
        }

        // Bucle de espera para el login (Si es visible, el usuario puede ayudar)
        let loginCheckCount = 0;
        while (page.url().includes('auth/signin') || page.url().includes('auth.immutable.com')) {
            loginCheckCount++;
            if (loginCheckCount === 1 && !IS_VISIBLE) {
                log("⏳ Esperando login... (Si se queda aquí, usa el modo VISIBLE)");
            }
            if (loginCheckCount > 30) { // 30 segundos
                log("❌ Tiempo de espera de login agotado.");
                if (!IS_VISIBLE) {
                    await takeDebugScreenshot(page, "login_timeout");
                    log("💡 TIP: Reinicia el Scout en Modo VISIBLE para loguear manualmente una vez.");
                    process.exit(1);
                }
            }
            await new Promise(r => setTimeout(r, 1000));
        }

        log("✅ Sesión detectada. ¡Listo para escanear!");
        await takeDebugScreenshot(page, "scan_start");

        // === LOOP DE ESCANEO ===
        log("🔍 Iniciando escaneo de lands...");

        let scannedCount = 0;

        while (true) {
            for (const landUrl of urlList) {
                try {
                    scannedCount++;
                    log(`[${scannedCount}] Escaneando: ${landUrl}`);

                    // Intentar navegar a la land
                    log(`🚀 Navegando...`);
                    const responsePromise = page.waitForResponse(
                        response => response.url().includes('/tiles/') && (response.status() === 200 || response.status() === 304),
                        { timeout: 15000 }
                    ).catch(() => null); // Silenciar error de timeout aquí para manejarlo después

                    await page.goto(landUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });

                    // Verificar si la navegación nos mandó al login (Sesión expirada)
                    if (page.url().includes('auth/signin')) {
                        log("⚠️ Redirigido a Sign-In. Intentando recuperar sesión...");
                        await takeDebugScreenshot(page, "session_expired_during_scan");

                        // Intentar volver a root para forzar auto-login de perfil
                        await page.goto('https://nomstead.com', { waitUntil: 'domcontentloaded' });
                        await new Promise(r => setTimeout(r, 5000));

                        if (page.url().includes('auth/signin')) {
                            log("❌ Sesión persistente perdida. Esperando re-login...");
                            // Si es visible, el usuario puede loguear. Si no, esperamos o reintentamos luego.
                            await new Promise(r => setTimeout(r, 10000));
                            continue;
                        } else {
                            log("✅ Sesión recuperada. Reintentando land...");
                            // Volver a empezar el ciclo para esta land
                        }
                    }

                    // Esperar respuesta de la API (si no falló antes)
                    const response = await responsePromise;
                    let json;
                    try {
                        json = await response.json();
                    } catch (jsonErr) {
                        log(`⚠️ No se pudo parsear JSON de la land (Status: ${response.status()}).`);
                        await takeDebugScreenshot(page, "json_error");
                        continue;
                    }

                    if (json && json.tile) {
                        const tileX = json.tile.x || 0;
                        const tileY = json.tile.y || 0;
                        const objects = json.tile.objects || [];
                        log(`📍 Ubicación actual: [${tileX}, ${tileY}] | Objetos: ${objects.length}`);

                        if (objects.length === 0) {
                            log("⚠️ Land sin objetos. ¿Carga incompleta?");
                            await takeDebugScreenshot(page, "zero_objects");
                        }

                        let foundResources = false;
                        let resourceType = "";
                        let detectedSlugs = [];

                        for (const obj of objects) {
                            const isTree = obj.slug && obj.slug.includes('tree');
                            const isRock = obj.slug && obj.slug.includes('rock');

                            // Guardar slugs para debug si no encontramos nada
                            if (detectedSlugs.length < 5 && obj.slug) detectedSlugs.push(obj.slug);

                            if (isTree || isRock) {
                                // DETALLE: Solo si el recurso está listo para ser recolectado
                                const isReady = obj.data && obj.data.ready === true;

                                if (isReady) {
                                    foundResources = true;
                                    resourceType = isTree ? "🌲 Árbol" : "🪨 Roca";
                                    break;
                                } else {
                                    // Log opcional para debug: log(`   ⏳ Saltando ${obj.slug} (No listo/Ready:false)`);
                                }
                            }
                        }

                        if (foundResources) {
                            log(`🎯 ¡RECURSOS ENCONTRADOS! ${resourceType} en ${landUrl}`);
                            await takeDebugScreenshot(page, "found_resource");

                            // Escribir señal
                            try {
                                fs.writeFileSync(FOUND_FILE, landUrl);
                            } catch (e) {
                                log(`❌ Error escribiendo ${FOUND_FILE}: ${e.message}`);
                            }

                            // Notificar Discord (si está configurado)
                            if (typeof notifyDiscord === 'function') notifyDiscord(landUrl, resourceType);

                            // Esperar dinámicamente a que AHK procese (borre el archivo)
                            log("⏳ Esperando que el bot principal procese el hallazgo...");
                            let waitStart = Date.now();
                            while (fs.existsSync(FOUND_FILE) && (Date.now() - waitStart < 30000)) {
                                await new Promise(r => setTimeout(r, 1000));
                            }

                            if (fs.existsSync(FOUND_FILE)) {
                                log("⚠️ Timeout esperando a AHK. Continuando escaneo...");
                                try { fs.unlinkSync(FOUND_FILE); } catch (e) { }
                            } else {
                                log("✅ Hallazgo procesado. Reanudando escaneo...");
                            }
                        } else {
                            if (scannedCount % 5 === 0) {
                                log(`🔍 Debug Slugs (Primeros 5): ${detectedSlugs.join(', ')}`);
                            }
                        }
                    } else {
                        log("⚠️ La land no devolvió datos válidos de tile. ¿Login fallido?");
                        await takeDebugScreenshot(page, "invalid_tile_data");
                    }

                } catch (e) {
                    log(`⚠️ Error escaneando ${landUrl}: ${e.message}`);
                    if (e.message.includes('timeout')) {
                        await takeDebugScreenshot(page, "timeout_error");
                    }
                }

                // Delay entre lands
                await new Promise(r => setTimeout(r, SCAN_DELAY));
            }

            log("🔄 Ciclo completado. Reiniciando desde el inicio...");
            if (DO_SHUFFLE) {
                log("🎲 Reshuffling URLs para la siguiente ronda...");
                shuffleArray(urlList);
            }
        }

    } catch (e) {
        log(`❌ Error crítico: ${e.message}`);
        process.exit(1);
    }
})();
