const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
const fs = require('fs');
const path = require('path');

puppeteer.use(StealthPlugin());

const TIMERS_FILE = path.join(__dirname, 'active_timers.json');
const LOG_FILE = path.join(__dirname, 'bot_debug.log');

// --- CONFIGURACIÓN DE TIEMPOS (HORAS) ---
const TIEMPOS = {
    "Arbol": { min: 6, max: 7 },       
    "Roca":  { min: 3, max: 4 },     
    "Construccion": { min: 23, max: 24 }
};

// --- MEMORIA GLOBAL (Para evitar race conditions) ---
let MEMORY_TIMERS = [];

function log(msg) {
    try {
        const time = new Date().toLocaleTimeString();
        fs.appendFileSync(LOG_FILE, `[${time}] ${msg}\n`);
    } catch (e) {}
}

// Cargar estado inicial
if (fs.existsSync(TIMERS_FILE)) {
    try {
        const raw = fs.readFileSync(TIMERS_FILE, 'utf8');
        if (raw.trim()) MEMORY_TIMERS = JSON.parse(raw);
    } catch (e) { MEMORY_TIMERS = []; }
} else {
    fs.writeFileSync(TIMERS_FILE, '[]');
}

// Función de guardado síncrono en memoria y disco
function updateDatabase(newTimer) {
    const now = Date.now();
    
    // 1. Limpiar expirados (más de 7h) de la memoria
    MEMORY_TIMERS = MEMORY_TIMERS.filter(t => t.finMax > (now - 25200000));

    // 2. Generar ID único
    const uniqueId = newTimer.objectId ? (newTimer.id + "_" + newTimer.objectId) : (newTimer.id + "_" + newTimer.finBase);

    // 3. Buscar si existe
    const index = MEMORY_TIMERS.findIndex(t => {
        const tUnique = t.objectId ? (t.id + "_" + t.objectId) : (t.id + "_" + t.finBase);
        return tUnique === uniqueId;
    });
    
    if (index !== -1) {
        MEMORY_TIMERS[index] = newTimer; // Actualizar
        log(`[UPD] ${newTimer.name} (${newTimer.id})`);
    } else {
        MEMORY_TIMERS.push(newTimer); // Agregar
        log(`[NEW] ${newTimer.name} (${newTimer.id})`);
    }

    // 4. Ordenar: El que termina antes va primero
    MEMORY_TIMERS.sort((a, b) => a.finBase - b.finBase);
    
    // 5. Volcar memoria a disco
    try {
        fs.writeFileSync(TIMERS_FILE, JSON.stringify(MEMORY_TIMERS, null, 2));
    } catch (e) {
        log("Error escribiendo archivo: " + e.message);
    }
}

(async () => {
    log("=== MONITOR MEMORIA ACTIVO v30.10 ===");
    try {
        const browser = await puppeteer.connect({
            browserURL: 'http://127.0.0.1:9222',
            defaultViewport: null
        });

        const targets = await browser.targets();
        const pageTarget = targets.find(t => t.url().includes('nomstead.com'));
        if (!pageTarget) return;

        const page = await pageTarget.page();

        page.on('request', async (request) => {
            const url = request.url();
            
            if (url.includes('/object/') && (url.includes('/cut') || url.includes('/mine') || url.includes('/build'))) {
                try {
                    const postData = request.postData(); 
                    if (!postData) return;

                    const jsonPayload = JSON.parse(postData);
                    const pathStr = jsonPayload.path; 

                    if (pathStr && pathStr.includes('/')) {
                        const parts = pathStr.split('/');
                        const landID = parts[0];
                        const objectID = parts[1];

                        let type = "Otro";
                        let name = "Objeto";
                        let timeConfig = { min: 1, max: 1.1 };

                        if (url.includes('tree')) { 
                            type = "Arbol"; name = "🌲 Tree"; timeConfig = TIEMPOS.Arbol;
                        } else if (url.includes('rock')) { 
                            type = "Roca"; name = "🪨 Rock"; timeConfig = TIEMPOS.Roca; 
                        } else if (url.includes('build')) {
                             type = "Construccion"; name = "🔨 Building"; timeConfig = TIEMPOS.Construccion;
                        }

                        const now = Date.now();
                        const finishBase = now + (timeConfig.min * 3600000);
                        const finishMax  = now + (timeConfig.max * 3600000);

                        let currentUrl = page.url();
                        if (!currentUrl.includes(landID)) {
                            currentUrl = `https://nomstead.com/u/${landID}`;
                        }

                        updateDatabase({
                            name: name,
                            type: type, // Usamos las keys internas para que AHK las entienda
                            finBase: finishBase,
                            finMax: finishMax,
                            url: currentUrl,
                            id: landID,         
                            objectId: objectID
                        });
                    }
                } catch (e) {}
            }
        });

        await new Promise(() => {}); 

    } catch (e) {
        log("Error: " + e.message);
    }
})();