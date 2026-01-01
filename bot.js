const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
const fs = require('fs');
const path = require('path');

puppeteer.use(StealthPlugin());

const TIMERS_FILE = path.join(__dirname, 'active_timers.json');
const LOG_FILE = path.join(__dirname, 'bot_debug.log');

// --- TIEMPOS (Horas) ---
const TIEMPOS = {
    "Arbol": { min: 6, max: 7 },
    "Roca":  { min: 4, max: 5 }, 
    "Construccion": { min: 23, max: 24 }
};

function log(msg) {
    try {
        const time = new Date().toLocaleTimeString();
        fs.appendFileSync(LOG_FILE, `[${time}] ${msg}\n`);
    } catch (e) {}
}

if (!fs.existsSync(TIMERS_FILE)) {
    fs.writeFileSync(TIMERS_FILE, '[]');
}

function saveTimer(newTimer) {
    let timers = [];
    try {
        if (fs.existsSync(TIMERS_FILE)) {
            const raw = fs.readFileSync(TIMERS_FILE, 'utf8');
            if (raw.trim()) {
                timers = JSON.parse(raw);
            }
        }
    } catch (e) { 
        timers = []; 
    }

    if (!Array.isArray(timers)) {
        timers = [];
    }

    // Limpiar expirados (mas de 7h vencidos)
    const now = Date.now();
    timers = timers.filter(t => t.finMax > (now - 25200000));

    // IMPORTANTE: Identificador único es LandID + ObjectID
    // Si no hay objectId, usamos el finBase como discriminador
    const uniqueId = newTimer.objectId ? (newTimer.id + "_" + newTimer.objectId) : (newTimer.id + "_" + newTimer.finBase);

    // Buscar si ya existe este objeto especifico
    const index = timers.findIndex(t => {
        const tUnique = t.objectId ? (t.id + "_" + t.objectId) : (t.id + "_" + t.finBase);
        return tUnique === uniqueId;
    });
    
    if (index !== -1) {
        timers[index] = newTimer; // Actualizar
        log(`[UPD] ${newTimer.name} en Land ${newTimer.id}`);
    } else {
        timers.push(newTimer); // Agregar nuevo
        log(`[NEW] ${newTimer.name} en Land ${newTimer.id}`);
    }

    // Ordenar por tiempo de finalización
    timers.sort((a, b) => a.finBase - b.finBase);
    
    try {
        fs.writeFileSync(TIMERS_FILE, JSON.stringify(timers, null, 2));
    } catch (e) {}
}

(async () => {
    log("=== MONITOR ACTIVO v30.4 ===");
    try {
        const browser = await puppeteer.connect({
            browserURL: 'http://127.0.0.1:9222',
            defaultViewport: null
        });

        const targets = await browser.targets();
        const pageTarget = targets.find(t => t.url().includes('nomstead.com'));
        if (!pageTarget) {
            return;
        }

        const page = await pageTarget.page();

        page.on('request', async (request) => {
            const url = request.url();
            
            if (url.includes('/object/') && (url.includes('/cut') || url.includes('/mine') || url.includes('/build'))) {
                try {
                    const postData = request.postData(); 
                    if (!postData) return;

                    const jsonPayload = JSON.parse(postData);
                    // Path suele ser: "LAND_ID/OBJECT_ID"
                    const pathStr = jsonPayload.path; 

                    if (pathStr && pathStr.includes('/')) {
                        const parts = pathStr.split('/');
                        const landID = parts[0];
                        const objectID = parts[1];

                        let type = "Otro";
                        let name = "Objeto";
                        let timeConfig = { min: 1, max: 1.1 };

                        if (url.includes('tree')) { 
                            type = "Arbol"; name = "🌲 Arbol"; timeConfig = TIEMPOS.Arbol;
                        } else if (url.includes('rock')) { 
                            type = "Roca"; name = "🪨 Roca"; timeConfig = TIEMPOS.Roca; 
                        } else if (url.includes('build')) {
                             type = "Construccion"; name = "🔨 Obra"; timeConfig = TIEMPOS.Construccion;
                        }

                        const now = Date.now();
                        const finishBase = now + (timeConfig.min * 3600000);
                        const finishMax  = now + (timeConfig.max * 3600000);

                        let currentUrl = page.url();
                        if (!currentUrl.includes(landID)) {
                            currentUrl = `https://nomstead.com/u/${landID}`;
                        }

                        saveTimer({
                            name: name,
                            type: type,
                            finBase: finishBase,
                            finMax: finishMax,
                            url: currentUrl,
                            id: landID,         
                            objectId: objectID  // CRUCIAL: Guardamos el ID del objeto
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