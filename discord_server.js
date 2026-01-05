const { Client, GatewayIntentBits, PermissionsBitField, ChannelType } = require('discord.js');
const fs = require('fs');
const express = require('express');
const bodyParser = require('body-parser');

// --- CÓDIGO ANTI-CIERRE ---
process.on('uncaughtException', (err) => { console.error('🔴 ERROR:', err); });
process.on('unhandledRejection', (reason) => { console.error('🔴 RECHAZO:', reason); });

// --- CONFIGURACIÓN ---
const TOKEN = process.env.DISCORD_TOKEN; // <--- PON TU TOKEN
const PORT = process.env.PORT || 3000; // Usa el puerto de Render o el 3000 si es local
const DB_USERS = 'usuarios_registrados.json';
const DB_TIMERS = 'global_timers.json'; // Nueva base de datos de tiempos

const client = new Client({
    intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages, GatewayIntentBits.MessageContent, GatewayIntentBits.GuildMembers]
});

const app = express();
app.use(bodyParser.json());

// --- CARGAR DATOS ---
let usersDB = {};
let timersDB = [];

if (fs.existsSync(DB_USERS)) try { usersDB = JSON.parse(fs.readFileSync(DB_USERS)); } catch (e) {}
if (fs.existsSync(DB_TIMERS)) try { timersDB = JSON.parse(fs.readFileSync(DB_TIMERS)); } catch (e) {}

function saveUsers() { fs.writeFileSync(DB_USERS, JSON.stringify(usersDB, null, 2)); }
function saveTimers() { fs.writeFileSync(DB_TIMERS, JSON.stringify(timersDB, null, 2)); }

function generarNombreRol(hwid, username) {
    const cleanUser = username.replace(/[^a-zA-Z0-9]/g, '');
    const cleanHwid = hwid.replace(/[^a-zA-Z0-9]/g, '');
    let result = "";
    const len = Math.max(cleanHwid.length, cleanUser.length);
    for (let i = 0; i < len; i++) {
        if (i < cleanHwid.length) result += cleanHwid[i];
        if (i < cleanUser.length) result += cleanUser[i];
    }
    return "K-" + result.substring(0, 25);
}

// --- API: RECIBIR TIMER DEL CLIENTE ---
app.post('/api/sync_timer', (req, res) => {
    const { hwid, name, type, id, finBase } = req.body;

    if (!hwid || !finBase) return res.status(400).send({ error: 'Datos incompletos' });

    // Verificar si el usuario existe
    const user = Object.values(usersDB).find(u => u.hwid === hwid);
    if (!user) return res.status(404).send({ error: 'Usuario no registrado' });

    // Crear ID único para el timer
    const uniqueId = `${hwid}_${id}_${finBase}`;

    // Evitar duplicados
    const exists = timersDB.some(t => t.uniqueId === uniqueId);
    if (exists) return res.send({ status: 'existe' });

    // Guardar en la nube
    timersDB.push({
        uniqueId,
        hwid,
        name,
        type,
        id, // ID del objeto en juego
        finBase, // Hora de aviso
        notified: false
    });
    
    // Ordenar y guardar
    timersDB.sort((a, b) => a.finBase - b.finBase);
    saveTimers();

    console.log(`[CLOUD] Timer guardado para ${user.discordName}: ${name}`);
    res.send({ status: 'ok' });
});

// --- BUCLE DEL SERVIDOR (CHEQUEA CADA 10 SEGUNDOS) ---
setInterval(async () => {
    const now = Date.now();
    let changed = false;

    // Recorremos los timers globales
    for (const timer of timersDB) {
        if (now >= timer.finBase && !timer.notified) {
            
            // Buscar al dueño
            const user = Object.values(usersDB).find(u => u.hwid === timer.hwid);
            
            if (user) {
                try {
                    const channel = await client.channels.fetch(user.channelID);
                    if (channel) {
                        let icon = "🔔";
                        if (timer.type === "Roca") icon = "🪨";
                        else if (timer.type === "Arbol") icon = "🌲";
                        else if (timer.type === "Construccion") icon = "🔨";

                        await channel.send(`${icon} **ALERTA DE TIMER**\n¡Tu **${timer.name}** está listo!\nID: ${timer.id}\n<@&${user.roleID}>`);
                        console.log(`[NOTIFY] Enviado a ${user.discordName} (PC Apagada o Encendida)`);
                    }
                } catch (e) {
                    console.error(`Error enviando a ${user.discordName}:`, e.message);
                }
            }
            
            timer.notified = true;
            changed = true;
        }
    }

    // Limpieza: Borrar timers notificados hace más de 1 hora
    const lenBefore = timersDB.length;
    timersDB = timersDB.filter(t => !t.notified || (now - t.finBase < 3600000));
    
    if (changed || timersDB.length !== lenBefore) {
        saveTimers();
    }

}, 10000);

// --- EVENTOS DISCORD ---
client.on('ready', () => {
    console.log(`✅ SERVIDOR MAESTRO ACTIVO: ${client.user.tag}`);
    app.listen(PORT, () => console.log(`🌐 Nube de Timers escuchando en puerto ${PORT}`));
});

client.on('messageCreate', async message => {
    if (message.author.bot) return;
    if (message.content.startsWith('!registrar')) {
        // (Mismo código de registro que ya tenías y funcionaba bien)
        const args = message.content.split(' ');
        const hwid = args[1];
        if (!hwid) return message.reply("❌ Falta HWID");
        if (usersDB[message.author.id]) return message.reply("⚠️ Ya registrado.");

        try {
            message.channel.send("🔄 Vinculando...");
            const guild = message.guild;
            const nombreRol = generarNombreRol(hwid, message.author.username);
            const rol = await guild.roles.create({ name: nombreRol, color: 'Random' });
            await message.member.roles.add(rol);
            const canal = await guild.channels.create({
                name: `log-${message.author.username}`,
                type: ChannelType.GuildText,
                permissionOverwrites: [
                    { id: guild.id, deny: [PermissionsBitField.Flags.ViewChannel] },
                    { id: rol.id, allow: [PermissionsBitField.Flags.ViewChannel] },
                    { id: client.user.id, allow: [PermissionsBitField.Flags.ViewChannel] }
                ]
            });
            usersDB[message.author.id] = { discordName: message.author.username, hwid, roleID: rol.id, channelID: canal.id };
            saveUsers();
            canal.send(`✅ **Sistema Cloud Activado.**\nTus timers se guardarán en el servidor.`);
            message.reply("✅ Listo.");
        } catch (e) { console.error(e); }
    }
});

client.login(TOKEN);