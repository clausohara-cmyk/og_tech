#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir

; ==============================================================================
; === CONFIGURACIÓN MADRE (EDITA ESTO AQUÍ Y OLVÍDATE DEL RESTO) ===
; ==============================================================================
; 1. El número de versión de ESTE script:
VERSION_DEL_SCRIPT := "27.7"

; 2. Enlaces de CONTROL (GitHub y Discord):
LINK_GITHUB_CONTROL := "https://raw.githubusercontent.com/clausohara-cmyk/og_tech/refs/heads/main/og-version.ini" 
global URL_BLACKLIST := "https://raw.githubusercontent.com/clausohara-cmyk/og_tech/refs/heads/main/blacklist.txt" ; <--- TU BLACKLIST.TXT
global URL_WEBHOOK   := "https://discord.com/api/webhooks/1455206228434223307/aHsXVona692-N_OSefoOQvghnWPYeQH8wSez971oInSfucoGdHq54l1wYkPxTeDiCxF3" ; <--- TU WEBHOOK

; 3. Variables Globales de Identidad (No tocar)
global MyHWID := "" 
global LicensedUntil := ""      
global IsLicenseValid := false  

; ==============================================================================
; SISTEMA DE SEGURIDAD Y ARRANQUE
; ==============================================================================

; --- DETECTOR DE CIERRE (Telemetría de Salida) ---
OnExit(AlCerrarPrograma) 

; --- LLAMADA PRINCIPAL DE VALIDACIÓN ---
ValidarLicencia() 

; --- FUNCIÓN PRINCIPAL DE VALIDACIÓN ---
ValidarLicencia() {
    global LicensedUntil, IsLicenseValid, MyHWID 
    
    SECRET_SALT := "MiClaveSecreta_SuperDificil_2025!" 
    ArchivoLicencia := "license.key"
    
    ; Obtener ID único del disco C
    try {
        MyHWID := DriveGetSerial("C:")
    } catch {
        MyHWID := "ERROR-HWID" 
    }
    
    ; --- 1. REVISIÓN DE BLACKLIST ONLINE (EL MARTILLO) ---
    if (EsUsuarioBaneado(URL_BLACKLIST, MyHWID)) {
        SoundBeep 300, 500 
        try FileDelete(ArchivoLicencia) 
        MsgBox("Tu licencia ha sido revocada remotamente.`nEl programa se cerrará en 5 segundos.", "⛔ ACCESO DENEGADO ⛔")
        ExitApp() 
    }
    
    ; --- 2. Verificación inicial al arrancar ---
    if FileExist(ArchivoLicencia) {
        try {
            SavedKey := FileRead(ArchivoLicencia)
            FechaExp := VerificarIntegridad(SavedKey, SECRET_SALT, MyHWID) 
            if (FechaExp != "") {
                LicensedUntil := FechaExp
                IsLicenseValid := true
                
                ; --- 3. REPORTE A DISCORD (EL OJO - ENTRADA) ---
                EnviarLogDiscord(URL_WEBHOOK, MyHWID, "🟢 Inicio de Sesión Exitoso", LicensedUntil)
            }
        }
    }
    
    ; --- 4. Si no hay licencia válida, mostrar ventana de bloqueo ---
    if (!IsLicenseValid) {
        MostrarVentanaActivacion(MyHWID)
    }
    
    ; --- 5. Iniciar el Timer de Verificación Constante ---
    if (IsLicenseValid) {
        ; El número al final (100) es la PRIORIDAD. 
        ; Hace que este chequeo interrumpa cualquier otra cosa que esté haciendo el script.
        SetTimer ChequearExpiracion, 60000, 100 
        ChequearExpiracion() 
    }
}

; --- GUI DE ACTIVACIÓN ---
MostrarVentanaActivacion(MyHWID) {
    AskGui := Gui("+AlwaysOnTop -MinimizeBox", "Activación de Software")
    AskGui.SetFont("s9", "Segoe UI")
    
    AskGui.Add("Text", "w350 Center", "Para usar este programa, envía este ID al administrador:")
    AskGui.SetFont("s12 bold")
    AskGui.Add("Edit", "w350 Center ReadOnly -E0x200", MyHWID) 
    AskGui.SetFont("s9 norm")
    
    AskGui.Add("Text", "w350 Center y+10", "Introduce la Key recibida:")
    KeyInput := AskGui.Add("Edit", "w350 Center Limit")
    
    Btn := AskGui.Add("Button", "w350 Default h40", "VALIDAR LICENCIA")
    
    idVentana := AskGui.Hwnd 
    Respuesta := ""

    Btn.OnEvent("Click", (*) => ProcesarInput())
    AskGui.OnEvent("Close", (*) => ExitApp()) 
    
    ProcesarInput() {
        global LicensedUntil, IsLicenseValid 
        
        InputVal := Trim(KeyInput.Value)
        if (InputVal == "") {
            MsgBox("Por favor, pega la licencia en el campo.", "Atención", 4096 + 48)
            return
        }
        
        SECRET_SALT := "MiClaveSecreta_SuperDificil_2025!" 
        ArchivoLicencia := "license.key"
        
        FechaExpVal := VerificarIntegridad(InputVal, SECRET_SALT, MyHWID) 

        if (FechaExpVal != "") {
            try {
                if FileExist(ArchivoLicencia)
                    FileDelete(ArchivoLicencia)
                FileAppend(InputVal, ArchivoLicencia)
                
                LicensedUntil := FechaExpVal 
                IsLicenseValid := true      
                
                MsgBox("¡Licencia Aceptada!`nBienvenido.", "Éxito", 4096 + 64)
                
                ; Reporte de activación exitosa (Opcional)
                EnviarLogDiscord(URL_WEBHOOK, MyHWID, "🟢 Licencia Activada Manualmente", LicensedUntil)
                
                Respuesta := "OK"
                AskGui.Destroy()
            } catch {
                MsgBox("Error al guardar la licencia.", "Error", 4096 + 16)
            }
        } else {
            MsgBox("Error: La licencia es incorrecta, expiró o no pertenece a esta PC.", "Licencia Inválida", 4096 + 16)
            KeyInput.Value := "" 
        }
    }
    
    AskGui.Show()
    
    while WinExist(idVentana)
        Sleep 100
        
    if (Respuesta == "OK") {
        SetTimer ChequearExpiracion, 30000 
        ChequearExpiracion() 
    } else {
        ExitApp() 
    }
}

; --- TIMER DE VERIFICACIÓN (AHORA CON "KILL SWITCH" EN TIEMPO REAL) ---
ChequearExpiracion() {
    global LicensedUntil, IsLicenseValid, MyHWID, URL_BLACKLIST
    
    ; OPTIMIZACIÓN: Si ya detectamos que no es válida, salimos para no saturar
    if (!IsLicenseValid || LicensedUntil = "")
        return 

    ; Usamos 'Critical' para que este chequeo no sea interrumpido por nada
    Critical "On"

    ; 1. Revisión de Blacklist
    if (EsUsuarioBaneado(URL_BLACKLIST, MyHWID)) {
        SoundBeep 300, 500
        try FileDelete("license.key")
        
        ; CAMBIO AQUÍ: Agregamos 4096 (System Modal) + IconHand + T5
        ; Esto hace que la ventana salga SI O SI encima de todo.
        MsgBox("Tu licencia ha sido revocada remotamente en tiempo real.`nEl programa se cerrará en 5 segundos.", "⛔ ACCESO REVOCADO ⛔")
        
        ExitApp()
    }

    ; 2. Revisión de Fecha
    HoraActual := FormatTime(, "yyyyMMddHHmmss")
    if (HoraActual > LicensedUntil) {
        MsgBox("¡Tu prueba ha terminado!`nContacta al administrador.", "Prueba Expirada", 4096 + 16)
        try FileDelete("license.key") 
        IsLicenseValid := false
        LicensedUntil := ""
        ExitApp() 
    }
}

; --- LÓGICA DE INTEGRIDAD ---
VerificarIntegridad(HexKey, Salt, LocalHWID) {
    try {
        RawStr := HexToStr(HexKey)
        if (RawStr == "")
            return ""

        Parts := StrSplit(RawStr, "|")
        if (Parts.Length != 2)
            return "" 
            
        FechaExp := Parts[1]
        FirmaOriginal := Parts[2]
        
        DataToCheck := FechaExp . LocalHWID . Salt
        FirmaCalculada := SimpleHash_V(DataToCheck)
        
        if (FirmaCalculada !== FirmaOriginal)
            return "" 
            
        HoraActual := FormatTime(, "yyyyMMddHHmmss")
        if (HoraActual > FechaExp)
            return "" 
            
        return FechaExp 
    } catch {
        return "" 
    }
}

; --- FUNCIONES AUXILIARES DE HASH ---
SimpleHash_V(str) {
    hash := 5381
    Loop Parse, str
        hash := ((hash << 5) + hash) + Ord(A_LoopField)
    return SubStr(Format("{:x}", hash), -8)
}

HexToStr(hex) {
    if (Mod(StrLen(hex), 2) != 0)
        return ""
    str := ""
    Loop (StrLen(hex) / 2) {
        byte := SubStr(hex, (A_Index-1)*2+1, 2)
        try str .= Chr("0x" byte)
    }
    return str
}

; ==============================================================================
; === FUNCIONES DE SEGURIDAD Y TELEMETRÍA (DISCORD & BLACKLIST) ===
; ==============================================================================

; Función para revisar si el HWID está en la lista negra de GitHub
EsUsuarioBaneado(urlRaw, localID) {
    if (urlRaw == "" || localID == "")
        return false
        
    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("GET", urlRaw, true)
        whr.Send()
        whr.WaitForResponse()
        blacklistContent := whr.ResponseText
        
        if InStr(blacklistContent, localID)
            return true
    } catch {
        return false 
    }
    return false
}

; Función para enviar el chivatazo a Discord (CORREGIDA - DATOS REALES)
EnviarLogDiscord(webhookUrl, hwid, accion, expiracion) {
    if (webhookUrl == "" || InStr(webhookUrl, "TU_WEBHOOK"))
        return

    try {
        PCName := EnvGet("COMPUTERNAME")
        UserName := EnvGet("USERNAME")
        
        ; Limpieza de caracteres peligrosos para JSON
        UserName := StrReplace(StrReplace(UserName, "\", ""), '"', "")
        PCName := StrReplace(StrReplace(PCName, "\", ""), '"', "")
        
        UsuarioCompleto := UserName " @ " PCName

        ; Plantilla JSON con marcadores
        jsonPayload := '
        (
        {
          "username": "Monitor de Seguridad",
          "avatar_url": "https://i.imgur.com/4M34hi2.png",
          "embeds": [
            {
              "title": "🔔 Actividad Detectada",
              "color": 65280,
              "fields": [
                { "name": "HWID", "value": "__HWID__", "inline": true },
                { "name": "Usuario PC", "value": "__USER__", "inline": true },
                { "name": "Acción", "value": "__ACCION__" },
                { "name": "Licencia Expira", "value": "__EXPIRA__" }
              ],
              "footer": { "text": "Sistema de Protección v27.1" }
            }
          ]
        }
        )'

        ; Reemplazo de marcadores con datos reales
        jsonPayload := StrReplace(jsonPayload, "__HWID__", hwid)
        jsonPayload := StrReplace(jsonPayload, "__USER__", UsuarioCompleto)
        jsonPayload := StrReplace(jsonPayload, "__ACCION__", accion)
        jsonPayload := StrReplace(jsonPayload, "__EXPIRA__", expiracion)

        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("POST", webhookUrl, false) ; false = Síncrono
        whr.SetRequestHeader("Content-Type", "application/json")
        whr.Send(jsonPayload)
        
    } catch {
        ; Silencio en caso de error
    }
}

; Función que se ejecuta AUTOMÁTICAMENTE al cerrar el programa
AlCerrarPrograma(ExitReason, ExitCode) {
    global MyHWID, URL_WEBHOOK, LicensedUntil, IsLicenseValid
    
    if (IsLicenseValid) {
        Razon := "Desconocida"
        switch ExitReason {
            case "Exit": Razon := "Cierre Normal (Botón Salir/Esc)"
            case "Menu": Razon := "Cierre desde Icono de Bandeja"
            case "Reload": Razon := "Reinicio (F5/Actualización)"
            case "Error": Razon := "Crash / Error Crítico"
            default: Razon := ExitReason
        }

        EnviarLogDiscord(URL_WEBHOOK, MyHWID, "🔴 Sesión Cerrada [" Razon "]", LicensedUntil)
    }
}

; ==============================================================================
; CLASE AUXILIAR GDI+
; ==============================================================================
class GDIPlus {
    __New() {
        this.hLib := DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
        si := Buffer(24, 0)
        NumPut("UInt", 1, si)
        this.pToken := 0
        if (this.hLib)
            DllCall("gdiplus\GdiplusStartup", "Ptr*", &pToken := 0, "Ptr", si, "Ptr", 0)
        this.pToken := pToken
    }
    Shutdown() {
        if (this.pToken)
            DllCall("gdiplus\GdiplusShutdown", "Ptr", this.pToken)
        if (this.hLib)
            DllCall("FreeLibrary", "Ptr", this.hLib)
    }
    CreateBitmapFromScreen(x, y, w, h) {
        hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
        hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdc, "Int", w, "Int", h)
        mdc := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
        obm := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
        DllCall("BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", hdc, "Int", x, "Int", y, "Int", 0x00CC0020)
        pBitmap := 0
        DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", hbm, "Ptr", 0, "Ptr*", &pBitmap := 0)
        DllCall("SelectObject", "Ptr", mdc, "Ptr", obm)
        DllCall("DeleteDC", "Ptr", mdc)
        DllCall("DeleteObject", "Ptr", hbm)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
        return pBitmap
    }
    SaveBitmapToFile(pBitmap, sOutput) {
        Extension := SubStr(sOutput, -3)
        CLSID := Buffer(16, 0)
        if (Extension = ".png")
            DllCall("ole32\CLSIDFromString", "WStr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", CLSID)
        else
            DllCall("ole32\CLSIDFromString", "WStr", "{557CF400-1A04-11D3-9A73-0000F81EF32E}", "Ptr", CLSID)
        DllCall("gdiplus\GdipSaveImageToFile", "Ptr", pBitmap, "WStr", sOutput, "Ptr", CLSID, "Ptr", 0)
    }
    DisposeImage(pBitmap) {
        DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
    }
}

; ==============================================================================
; INICIALIZACIÓN Y HOTKEYS
; ==============================================================================
if !DirExist("Capturas")
    DirCreate("Capturas")

; Aquí inyectamos la configuración del inicio a la clase principal
App := GestorApertura(VERSION_DEL_SCRIPT, LINK_GITHUB_CONTROL)

; --- HOTKEYS GLOBALES ---
F2::App.MostrarInterfaz()
F3::App.AlternarPausa()
F4::App.VerEventosMouse()
F5::Reload()

; --- HOTKEYS INTERFAZ PRINCIPAL ---
#HotIf (App.GuiActiva != 0 && WinExist("ahk_id " App.GuiActiva.Hwnd) && WinActive("ahk_id " App.GuiActiva.Hwnd))
Esc:: {
    if (App.IsEditingText()) {
        Send("{Esc}") 
        return
    }
    if (App.Expandido)
        App.TogglePanel()
    else
        App.MinimizarOcultar()
}
Tab::App.TogglePanel()
#HotIf

; ==============================================================================
; CLASE PRINCIPAL
; ==============================================================================
class GestorApertura {
    ; Modificado para recibir argumentos del inicio
    __New(verScript, linkRaw) {
        this.VersionActual := verScript
        this.URL_CONTROL := linkRaw
        
        this.InitIdiomas() 
        this.Idioma := "ES"
        this.CaptureKey := "F1"
        this.ExtraCooldown := 1400
        
        this.UpdateData := {Exeter: "", Ver: "", Msg: ""} 
        this.BtnUpdate := 0 

        this.KeyMacroFoto := "1"
        this.KeyMacroCoord := "2"
        this.KeyAreaSel := "1"
        this.KeyStopLoop := "F6" 

        this.Eventos := []
        this.Historial := [] 
        this.Lib := [[], [], []]
        loop 3 {
            c := A_Index
            loop 100
                this.Lib[c].Push("")
        }

        this.ColNames := ["Videos", "Social", "Trabajo"]
        this.ConfigPath := "config_programacion.ini"
        this.Pausado := false
        this.Navegador := "chrome.exe"
        this.TempMacroPasos := []

        this.CurrentStepIndex := 0
        this.CurrentMacroArray := []

        this.ExtraActivo := false
        this.ExtraTimerOn := false
        this.EjecutandoExtra := false
        
        this.EnEsperaRecurrencia := false
        this.EventoCongeladoRef := "" 
        this.DatosEventoRecurrente := ""
        this.EjecutandoLoopInfinito := false
        
        this.ControlTips := Map() 
        this.LastTipHwnd := 0
        OnMessage(0x0200, this.CheckHoverToolTip.Bind(this))

        this.OpcionesNav := Map("Google Chrome","chrome.exe","Mozilla Firefox","firefox.exe","Microsoft Edge","msedge.exe","Opera GX","opera.exe")
        this.GuiActiva := 0
        this.GuiMacros := 0
        this.GuiExtra := 0
        this.RecurGui := 0 
        this.Expandido := false
        this.GDI := GDIPlus()

        this.CargarDatos()
        this.ExtraPasosData := this.CargarExtraDatos()

        this.StopLoopBinder := this.DetenerLoopForzado.Bind(this)

        ; --- IMPORTANTE: Aquí se llama al Timer del Reloj ---
        SetTimer(() => this.ActualizarReloj(), 1000)
        
        SetTimer(() => this.VerificarHorarios(), 1000)
        SetTimer(() => this.LimpiarHistorialAuto(), 5000)
        
        SetTimer(() => this.VerificarActualizacionNube(), 2000)
        
        this.MostrarInterfaz()
    }

    __Delete() {
        try {
            this.GDI.Shutdown()
        }
    }

    ; ==========================================================================
    ; SECCIÓN 0: UTILIDADES, IDIOMAS Y ACTUALIZACIÓN
    ; ==========================================================================
    T(key) {
        if (this.LangData.Has(this.Idioma) && this.LangData[this.Idioma].Has(key))
            return this.LangData[this.Idioma][key]
        if (this.LangData.Has("ES") && this.LangData["ES"].Has(key))
            return this.LangData["ES"][key]
        return "[" key "]"
    }

    InitIdiomas() {
        this.LangData := Map()
        
        this.LangData["ES"] := Map(
            "Title", "AutoApertura Vision v" this.VersionActual,
            "GrpProg", "Programador Automático",
            "LblHora", "Hora:", "LblURL", "URL:",
            "BtnAdd", "Añadir +", "BtnMacros", "⚙️ Macros",
            "LblNav", "Nav:", 
            "BtnHelp", "❓", "TipHelp", "Ayuda / Atajos",
            "BtnLang", "🌐", "TipLang", "Cambiar Idioma",
            "BtnExtra", "⭐ EXTRA (20 Pasos)", "TipExtra", "Monitor Imágenes",
            "GrpLib", "Biblioteca Permanente", "ColStep", "Paso", "ColStatus", "Jerarquía",
            "SelStepInfo", "Selecione paso. Marque para proteger Hijos.",
            "ListStep", "Pasos:", "GrpConfig", "Configuración", "SelStepPlace", "Selecciona...",
            "LblType", "Acción:", "StsEmpty", "Vacío", "StsImg", "IMG", "StsCoord", "COORD",
            "BtnFoto", "📷 FOTO", "BtnCoord", "📍 COORD",
            "LblSearch", "Buscar/Espera (ms):", "LblPreClick", "Pre-Click (ms):",
            "ChkTurbo", "Turbo Click", "LblDur", "Duración (ms):", "BtnZone", "📍 ZONA",
            "LblCoordInfo", "Coord:", "BtnSave", "GUARDAR", "BtnClean", "Limpiar",
            "BtnMonOn", "ACTIVAR MONITOR", "BtnMonOff", "DETENER MONITOR",
            "BtnManual", "📘", "TipManual", "Manual",
            "MsgAdded", "Evento Agregado.", "MsgSaved", "Configuración Guardada.",
            "TipSum", "Sumar tiempo (min 10s, max 24h)",
            "MsgHelp", "ATAJOS:`n`nF2: Interfaz`nF3: Pausa`nF4: Info`nF5: Recargar",
            "TipCoord", "MUEVE Y PULSA: ", "TipClick", "COORD CLICK (TECLA: ",
            "NoteTime", "1000 ms = 1 seg.", "ChkRecur", "Recurrente",
            "MsgRecurTime", "Ciclo completado.`nIngrese tiempo a sumar:", "MsgRecurTitle", "RE-PROGRAMAR",
            "ChkSinHora", "Manual", "BtnLoopManual", "▶ Iniciar Loop ∞ (Manual)",
            "GrpExecTools", "Herramientas de Ejecución", "LblStopKey", "Tecla Stop Loop:",
            "LblRecurDone", "Tiempo de Link Completado", "LblRecurAdd", "¿Sumar cuánto? (HHMMSS):`nMin:10s - Max:24h",
            "BtnRecurOK", "ACEPTAR", "BtnRecurCancel", "CANCELAR",
            "ManMainTitle", "MANUAL", "ManMainText", "v" this.VersionActual " PRO.",
            "ManMacroTitle", "MANUAL MACROS", "ManMacroText", "Panel izquierdo: selección. Panel derecho: configuración.", 
            "ManExtraTitle", "MANUAL EXTRA", "ManExtraText", "Sistema de monitoreo.",
            "GrpHist", "Historial Reciente (Max 1h)",
            "ErrTimeRange", "⚠️ Rango Invalido!`nMín: 10 seg (000010)`nMáx: 24h (240000)",
            "BtnUpdate", "New Update"
        )
        
        this.LangData["EN"] := this.LangData["ES"].Clone()
        this.LangData["EN"]["Title"] := "Auto Vision Scheduler v" this.VersionActual " PRO"
        this.LangData["EN"]["GrpHist"] := "History (Max 1h)"
        this.LangData["EN"]["BtnRecurCancel"] := "CANCEL"
        this.LangData["EN"]["ErrTimeRange"] := "⚠️ Invalid Range!`nMin: 10 sec`nMax: 24h"
        this.LangData["EN"]["BtnUpdate"] := "New Update"
    }
    
    VerificarActualizacionNube() {
        if (this.URL_CONTROL == "" || InStr(this.URL_CONTROL, "TU_USUARIO")) {
             return 
        }
        
        try {
            whr := ComObject("WinHttp.WinHttpRequest.5.1")
            whr.Open("GET", this.URL_CONTROL, true)
            whr.Send()
            whr.WaitForResponse()
            
            rawText := whr.ResponseText
            vNube := this.LeerValorIniTexto(rawText, "Version")
            eNube := this.LeerValorIniTexto(rawText, "Estado")
            lNube := this.LeerValorIniTexto(rawText, "Link")
            mNube := this.LeerValorIniTexto(rawText, "Msg")
            
            if (vNube != "" && vNube > this.VersionActual && eNube == "LIBERADO") {
                this.UpdateData.Ver := vNube
                this.UpdateData.Exeter := lNube
                this.UpdateData.Msg := mNube
                
                if (this.BtnUpdate != 0) {
                    this.BtnUpdate.Visible := true
                    this.BtnUpdate.Text := this.T("BtnUpdate") . " (v" vNube ")"
                    SoundBeep 1000, 300
                    try TrayTip "Nueva Versión: v" vNube, "Actualización", 1
                }
            }
        }
    }
    
    LeerValorIniTexto(txt, key) {
        Loop Parse, txt, "`n", "`r" {
            if (InStr(A_LoopField, key "=")) {
                return Trim(StrSplit(A_LoopField, "=", , 2)[2])
            }
        }
        return ""
    }
    
    ; --- ACTUALIZADOR BLINDADO Y SEGURO ---
    EjecutarUpdate() {
        if (this.UpdateData.Exeter == "")
            return
            
        res := MsgBox("¿Deseas descargar e instalar la versión v" this.UpdateData.Ver "?`n`nNota: " this.UpdateData.Msg, "Actualización", "YesNo Icon?")
        if (res == "No")
            return
            
        try {
            tempName := "Update_" A_TickCount ".tmp"
            
            try {
                Download(this.UpdateData.Exeter, tempName)
            } catch {
                MsgBox("Error: No se pudo conectar con el servidor de descarga.", "Error de Red", 16)
                return
            }

            ; VERIFICACIÓN DE SEGURIDAD: Evita borrar archivos si la descarga falló
            if (FileGetSize(tempName) < 10) {
                MsgBox("Error Crítico: Archivo corrupto. Actualización cancelada.", "Error", 16)
                FileDelete(tempName)
                return
            }
            
            scriptPath := A_ScriptFullPath
            tempPath   := A_ScriptDir "\" tempName
            batPath    := A_ScriptDir "\update.bat"

            batContent := "
            (
            @echo off
            timeout /t 2 /nobreak >nul
            del /f /q `"" scriptPath "`"
            move /y `"" tempPath "`" `"" scriptPath "`"
            start `"" scriptPath "`"
            del `"" batPath "`"
            )"
            
            if FileExist(batPath)
                FileDelete(batPath)
            FileAppend(batContent, batPath)
            
            Run batPath
            ExitApp 
        } catch as err {
            MsgBox("Error inesperado: " err.Message, "Error", 16)
        }
    }

    ; --- ¡AQUÍ ESTÁ LA FUNCIÓN QUE FALTABA! ---
    ActualizarReloj() {
        if (this.GuiActiva && WinExist(this.GuiActiva.Hwnd)) {
            try this.EditHora.Text := FormatTime(, "HHmmss")
        }
    }

    EsTiempoValido(strTime) {
        if (!IsInteger(strTime) || StrLen(strTime) != 6)
            return false
        HH := Integer(SubStr(strTime, 1, 2))
        MM := Integer(SubStr(strTime, 3, 2))
        SS := Integer(SubStr(strTime, 5, 2))
        totalSegundos := (HH * 3600) + (MM * 60) + SS
        if (totalSegundos < 10 || totalSegundos > 86400)
            return false
        return true
    }

    IsConfigOpen() {
        try {
            if (IsObject(this.GuiMacros) && WinExist("ahk_id " this.GuiMacros.Hwnd))
                return true
        } 
        try {
            if (IsObject(this.GuiExtra) && WinExist("ahk_id " this.GuiExtra.Hwnd))
                return true
        }
        return false
    }

    IsEditingText() {
        try {
            ctrl := ControlGetClassNN(ControlGetFocus("A"))
            if (InStr(ctrl, "Edit") || InStr(ctrl, "Hot"))
                return true
        } 
        return false
    }

    ; ==========================================================================
    ; SECCIÓN 1: DATOS
    ; ==========================================================================
    CargarDatos() {
        if !FileExist(this.ConfigPath)
            return
        try {
            this.Navegador := IniRead(this.ConfigPath, "Config", "Navegador", "chrome.exe")
            this.Idioma := IniRead(this.ConfigPath, "Config", "Idioma", "ES")
            this.CaptureKey := IniRead(this.ConfigPath, "Config", "CaptureKey", "F1")
            this.ExtraCooldown := Integer(IniRead(this.ConfigPath, "Config", "ExtraCooldown", "1400"))

            this.KeyMacroFoto := IniRead(this.ConfigPath, "Config", "KeyMacroFoto", "1")
            this.KeyMacroCoord := IniRead(this.ConfigPath, "Config", "KeyMacroCoord", "2")
            this.KeyAreaSel := IniRead(this.ConfigPath, "Config", "KeyAreaSel", "1")
            this.KeyStopLoop := IniRead(this.ConfigPath, "Config", "KeyStopLoop", "F6")

            loop 3 {
                cIdx := A_Index
                this.ColNames[cIdx] := IniRead(this.ConfigPath, "Config", "ColName" cIdx, this.ColNames[cIdx])
                contLib := IniRead(this.ConfigPath, "Lib" cIdx, , "")
                if (contLib != "") {
                    for linea in StrSplit(contLib, "`n") {
                        linea := Trim(linea, " `t`r")
                        if InStr(linea, "=") {
                            p := StrSplit(linea, "=", , 2)
                            idx := Integer(p[1])
                            if (idx >= 1 && idx <= 100)
                                this.Lib[cIdx][idx] := Trim(p[2])
                        }
                    }
                }
            }

            contProg := IniRead(this.ConfigPath, "Eventos", , "")
            if (contProg != "") {
                for l in StrSplit(contProg, "`n") {
                    l := Trim(l, " `t`r")
                    if (l == "")
                        continue
                    if InStr(l, "=") {
                        key := Trim(StrSplit(l, "=", , 2)[1])
                        val := Trim(StrSplit(l, "=", , 2)[2])
                        parts := StrSplit(val, "|")
                        horaCargada := "", urlCargada := "", esRecurrente := 0

                        if (parts.Length >= 2) {
                            horaCargada := Trim(parts[1])
                            urlCargada := Trim(parts[2])
                            if (parts.Length >= 3)
                                esRecurrente := Integer(Trim(parts[3]))
                        } else {
                            if (IsInteger(key) && StrLen(key) == 6) {
                                horaCargada := key
                                urlCargada := val
                            } else if (key == "MANUAL") {
                                horaCargada := "MANUAL"
                                urlCargada := val
                            } else {
                                horaCargada := "000000"
                                urlCargada := val
                            }
                        }
                        evObj := {Hora: horaCargada, URL: urlCargada, Recurrente: esRecurrente}
                        macrosRaw := IniRead(this.ConfigPath, "Macros_" key, , "")
                        if (macrosRaw != "") {
                            evObj.Macros := []
                            for mLine in StrSplit(macrosRaw, "`n") {
                                mLine := Trim(mLine, " `t`r")
                                if InStr(mLine, "=") {
                                    mVal := StrSplit(mLine, "=", , 2)[2]
                                    mObj := this.ParsearMacroString(mVal)
                                    evObj.Macros.Push(mObj)
                                }
                            }
                        }
                        this.Eventos.Push(evObj)
                    }
                }
            }
            this.OrdenarEventos()
        } 
    }

    ParsearMacroString(str) {
        parts := StrSplit(str, "|")
        mObj := {ImgPath: parts[1], DelayBuscar: Integer(parts[2]), DelayClick: Integer(parts[3])}
        if (parts.Length >= 4) {
            z := StrSplit(parts[4], ":")
            mObj.Zone := {X: Integer(z[1]), Y: Integer(z[2]), W: Integer(z[3]), H: Integer(z[4])}
        }
        if (parts.Length >= 5)
            mObj.MultiClick := Integer(parts[5])
        if (parts.Length >= 6)
            mObj.MultiDur := Integer(parts[6])
        if (parts.Length >= 8) {
            mObj.ClickX := Integer(parts[7])
            mObj.ClickY := Integer(parts[8])
        }
        if (parts.Length >= 10) {
            tX := Integer(parts[9])
            tY := Integer(parts[10])
            if (tX > 0 || tY > 0) {
                mObj.TargetX := tX
                mObj.TargetY := tY
            }
        }
        if (parts.Length >= 11)
            mObj.NoClick := Integer(parts[11])
        if (parts.Length >= 13) {
            mObj.Randomize := Integer(parts[12])
            mObj.RandomRange := Integer(parts[13])
        } else {
            mObj.Randomize := 0
            mObj.RandomRange := 5
        }
        if (parts.Length >= 15) {
            mObj.ClickInterval := Integer(parts[14])
            mObj.InfiniteLoop := Integer(parts[15])
        } else {
            mObj.ClickInterval := 40
            mObj.InfiniteLoop := 0
        }
        if (parts.Length >= 16)
            mObj.SkipBlockIfFail := Integer(parts[16])
        else
            mObj.SkipBlockIfFail := 0
        return mObj
    }

    ConstruirMacroString(mac) {
        mStr := mac.ImgPath "|" mac.DelayBuscar "|" mac.DelayClick
        if (mac.HasOwnProp("Zone"))
            mStr .= "|" mac.Zone.X ":" mac.Zone.Y ":" mac.Zone.W ":" mac.Zone.H
        mStr .= "|" (mac.HasOwnProp("MultiClick") ? mac.MultiClick : 0)
        mStr .= "|" (mac.HasOwnProp("MultiDur") ? mac.MultiDur : 1000)
        mStr .= "|" (mac.HasOwnProp("ClickX") ? mac.ClickX : 0)
        mStr .= "|" (mac.HasOwnProp("ClickY") ? mac.ClickY : 0)
        if (mac.HasOwnProp("TargetX"))
            mStr .= "|" mac.TargetX "|" mac.TargetY
        else
            mStr .= "|0|0"
        mStr .= "|" (mac.HasOwnProp("NoClick") ? mac.NoClick : 0)
        mStr .= "|" (mac.HasOwnProp("Randomize") ? mac.Randomize : 0)
        mStr .= "|" (mac.HasOwnProp("RandomRange") ? mac.RandomRange : 5)
        mStr .= "|" (mac.HasOwnProp("ClickInterval") ? mac.ClickInterval : 40)
        mStr .= "|" (mac.HasOwnProp("InfiniteLoop") ? mac.InfiniteLoop : 0)
        mStr .= "|" (mac.HasOwnProp("SkipBlockIfFail") ? mac.SkipBlockIfFail : 0)
        return mStr
    }

    GuardarDatos() {
        if FileExist(this.ConfigPath)
            FileDelete(this.ConfigPath)
        IniWrite(this.Navegador, this.ConfigPath, "Config", "Navegador")
        IniWrite(this.Idioma, this.ConfigPath, "Config", "Idioma")
        IniWrite(this.CaptureKey, this.ConfigPath, "Config", "CaptureKey")
        IniWrite(this.ExtraCooldown, this.ConfigPath, "Config", "ExtraCooldown")
        IniWrite(this.KeyMacroFoto, this.ConfigPath, "Config", "KeyMacroFoto")
        IniWrite(this.KeyMacroCoord, this.ConfigPath, "Config", "KeyMacroCoord")
        IniWrite(this.KeyAreaSel, this.ConfigPath, "Config", "KeyAreaSel")
        IniWrite(this.KeyStopLoop, this.ConfigPath, "Config", "KeyStopLoop")

        loop 3 {
            cIdx := A_Index
            IniWrite(this.ColNames[cIdx], this.ConfigPath, "Config", "ColName" cIdx)
            for i, url in this.Lib[cIdx] {
                if (url != "")
                    IniWrite(url, this.ConfigPath, "Lib" cIdx, i)
            }
        }
        for i, ev in this.Eventos {
            key := "Ev" i
            isRec := (ev.HasOwnProp("Recurrente") ? ev.Recurrente : 0)
            IniWrite(ev.Hora "|" ev.URL "|" isRec, this.ConfigPath, "Eventos", key)
            if (ev.HasOwnProp("Macros")) {
                for j, mac in ev.Macros {
                    IniWrite(this.ConstruirMacroString(mac), this.ConfigPath, "Macros_" key, j)
                }
            }
        }
        this.GuardarExtraDatosDisk()
    }

    CargarExtraDatos() {
        arr := []
        loop 20 {
            raw := IniRead(this.ConfigPath, "Extra", "Paso" A_Index, "")
            obj := ""
            if (raw != "") {
                obj := this.ParsearMacroString(raw)
            }
            arr.Push(obj)
        }
        return arr
    }

    GuardarExtraDatosDisk() {
        for i, data in this.ExtraPasosData {
            if (IsObject(data)) {
                str := this.ConstruirMacroString(data)
                IniWrite(str, this.ConfigPath, "Extra", "Paso" i)
            } else {
                IniWrite("", this.ConfigPath, "Extra", "Paso" i)
            }
        }
    }

    OrdenarEventos() {
        if (this.Eventos.Length < 2)
            return
        
        loop this.Eventos.Length - 1 {
            i := A_Index
            loop this.Eventos.Length - i {
                j := A_Index
                h1 := this.Eventos[j].Hora
                h2 := this.Eventos[j+1].Hora
                if (h1 > h2) {
                    temp := this.Eventos[j]
                    this.Eventos[j] := this.Eventos[j+1]
                    this.Eventos[j+1] := temp
                }
            }
        }
    }

    ; ==========================================================================
    ; SECCIÓN 2: INTERFAZ REDISEÑADA Y COMPACTA
    ; ==========================================================================
    MostrarInterfaz() {
        if (this.GuiActiva != 0 && WinExist(this.GuiActiva.Hwnd)) {
            this.GuiActiva.Show()
            return
        }

        miGui := Gui("-MinimizeBox", this.T("Title"))
        this.GuiActiva := miGui
        miGui.SetFont("s9", "Segoe UI")
        
        miGui.SetFont("bold cRed")
        this.BtnUpdate := miGui.Add("Button", "x130 y8 w140 h22 Hidden", this.T("BtnUpdate"))
        this.BtnUpdate.OnEvent("Click", (*) => this.EjecutarUpdate())
        miGui.SetFont("norm cDefault")

        miGui.Add("GroupBox", "x10 y35 w380 h560", this.T("GrpProg"))
        
        miGui.Add("Text", "x20 y60 w40", this.T("LblHora"))
        this.EditHora := miGui.Add("Text", "x60 y58 w70 h20 +Border +0x200 +Center", FormatTime(, "HHmmss"))
        
        this.ChkSumar := miGui.Add("Checkbox", "x140 y58 w30", "+")
        this.ChkSumar.OnEvent("Click", (*) => this.ToggleSumarUI())
        this.AddToolTipToCtrl(this.ChkSumar, this.T("TipSum"))
        
        this.EditOffset := miGui.Add("Edit", "x170 y58 w55 Limit6 Number", "000000")
        this.EditOffset.Enabled := false

        this.ChkSinHora := miGui.Add("Checkbox", "x240 y58 w130", this.T("ChkSinHora"))
        this.ChkSinHora.OnEvent("Click", (*) => this.ToggleSinHora())

        miGui.Add("Text", "x20 y90 w40", this.T("LblURL"))
        this.EditURL := miGui.Add("Edit", "x60 y88 w200", "")
        
        this.ChkSoloMacro := miGui.Add("Checkbox", "x270 y88 w110", "Solo Macro")
        this.ChkSoloMacro.OnEvent("Click", (*) => this.ToggleSoloMacroUI())

        this.ChkRecurrente := miGui.Add("Checkbox", "x20 y125 w150", "🔄 " this.T("ChkRecur"))
        
        miGui.Add("Button", "x175 y120 w80 h30 Default", this.T("BtnAdd")).OnEvent("Click", (*) => this.AgregarProg())
        miGui.Add("Button", "x265 y120 w110 h30", this.T("BtnMacros")).OnEvent("Click", (*) => this.AbrirConfigMacros(100, this.TempMacroPasos, "Macros Link"))

        this.LV_Prog := miGui.Add("ListView", "x20 y160 w360 h150 Grid -Multi", ["Hora", "URL", "Info"])
        this.LV_Prog.ModifyCol(1, 60)
        this.LV_Prog.ModifyCol(2, 230)
        this.LV_Prog.ModifyCol(3, 50)
        this.LV_Prog.OnEvent("DoubleClick", (lv, row) => this.EliminarProg(row))
        this.LV_Prog.OnEvent("ItemSelect", this.ChequearBotonLoop.Bind(this))
        
        miGui.Add("Text", "x20 y315 w200 h15", this.T("GrpHist"))
        this.LV_Hist := miGui.Add("ListView", "x20 y330 w360 h75 Grid -Multi", ["Hora Fin", "Link / Estado"])
        this.LV_Hist.ModifyCol(1, 70)
        this.LV_Hist.ModifyCol(2, 260)
        this.LV_Hist.OnEvent("DoubleClick", (lv, row) => this.EliminarHistorial(row))
        
        miGui.SetFont("bold cBlue")
        this.BtnRunLoop := miGui.Add("Button", "x20 y415 w360 h30 Disabled", this.T("BtnLoopManual"))
        this.BtnRunLoop.OnEvent("Click", (*) => this.EjecutarMacroLoopInfinito())
        miGui.SetFont("norm cDefault")

        miGui.Add("Text", "x20 y453", this.T("LblNav"))
        nombresNav := []
        posInicial := 1
        for nombre, exe in this.OpcionesNav {
            nombresNav.Push(nombre)
            if (exe = this.Navegador)
                posInicial := nombresNav.Length
        }
        miGui.Add("DropDownList", "x55 y450 w160 Choose" posInicial, nombresNav).OnEvent("Change", (c,*) => this.CambiarNav(c.Text))

        this.BtnManual := miGui.Add("Button", "x225 y450 w30 h25", this.T("BtnManual"))
        this.BtnManual.OnEvent("Click", (*) => this.AbrirManualPersonalizado(this.T("ManMainTitle"), this.T("ManMainText")))
        this.AddToolTipToCtrl(this.BtnManual, this.T("TipManual"))

        this.BtnHelp := miGui.Add("Button", "x260 y450 w30 h25", this.T("BtnHelp"))
        this.BtnHelp.OnEvent("Click", (*) => this.MostrarAyuda())
        this.AddToolTipToCtrl(this.BtnHelp, this.T("TipHelp"))

        this.BtnLang := miGui.Add("Button", "x295 y450 w30 h25", this.T("BtnLang"))
        this.BtnLang.OnEvent("Click", (*) => this.CambiarIdiomaMenu())
        this.AddToolTipToCtrl(this.BtnLang, this.T("TipLang"))

        miGui.Add("GroupBox", "x20 y485 w360 h60", this.T("GrpExecTools"))
        
        miGui.Add("Text", "x30 y510", this.T("LblStopKey"))
        this.HKStop := miGui.Add("Hotkey", "x130 y506 w80", this.KeyStopLoop)
        this.HKStop.OnEvent("Change", (*) => this.GuardarTeclaStop())

        miGui.SetFont("s9 bold")
        this.BtnExtra := miGui.Add("Button", "x230 y505 w140 h30 cBlue", this.T("BtnExtra"))
        this.BtnExtra.OnEvent("Click", (*) => this.MostrarInterfazExtra())
        this.AddToolTipToCtrl(this.BtnExtra, this.T("TipExtra"))
        miGui.SetFont("s9 norm")

        this.BtnExp := miGui.Add("Button", "x395 y220 w20 h80", ">")
        this.BtnExp.OnEvent("Click", (*) => this.TogglePanel())

        miGui.Add("GroupBox", "x420 y5 w550 h590", this.T("GrpLib"))
        this.LV_L1 := miGui.Add("ListView", "x430 y25 w175 h560 Grid -Multi", ["#", this.ColNames[1]])
        this.LV_L2 := miGui.Add("ListView", "x+5 yp w175 h560 Grid -Multi", ["#", this.ColNames[2]])
        this.LV_L3 := miGui.Add("ListView", "x+5 yp w175 h560 Grid -Multi", ["#", this.ColNames[3]])

        loop 3 {
            lv := this.%"LV_L" A_Index%
            lv.ModifyCol(1, 35)
            lv.ModifyCol(2, 135)
            lv.OnEvent("Click", (l, r) => this.ClickLib(l, r))
            lv.OnEvent("DoubleClick", (l, r) => this.EditLib(l, r))
            lv.OnEvent("ContextMenu", (l, r, *) => this.MenuLib(l, r))
        }

        this.ActualizarInterfazVisual()
        miGui.OnEvent("Close", (*) => ExitApp())
        miGui.Show("w420 h610") 
    }

    AddToolTipToCtrl(ctrlObj, text) {
        this.ControlTips[ctrlObj.Hwnd] := text
    }

    CheckHoverToolTip(wParam, lParam, msg, hwnd) {
        if (this.ControlTips.Has(hwnd)) {
            if (this.LastTipHwnd != hwnd) {
                text := this.ControlTips[hwnd]
                ToolTip(text)
                this.LastTipHwnd := hwnd
                SetTimer(this.ClearTipBinder := (() => ToolTip()), -2000)
            }
        } else {
            if (this.LastTipHwnd != 0) {
                ToolTip()
                this.LastTipHwnd := 0
            }
        }
    }

    ToggleSinHora() {
        val := this.ChkSinHora.Value
        if val {
            this.EditHora.Opt("cGray")
            this.EditHora.Text := "MANUAL"
            this.ChkSumar.Enabled := false
            this.EditOffset.Enabled := false
        } else {
            this.EditHora.Opt("cDefault")
            this.EditHora.Text := FormatTime(, "HHmmss") 
            this.ChkSumar.Enabled := true
            this.ToggleSumarUI()
        }
    }

    GuardarTeclaStop() {
        if (this.HKStop.Value != "") {
            this.KeyStopLoop := this.HKStop.Value
            this.GuardarDatos()
        }
    }

    ChequearBotonLoop(lv, item, selected) {
        if (selected) {
            if (item > 0 && item <= this.Eventos.Length) {
                this.BtnRunLoop.Enabled := true
                return
            }
        }
        this.BtnRunLoop.Enabled := false
    }

    DetenerLoopForzado(*) {
        if (this.EjecutandoLoopInfinito) {
            this.EjecutandoLoopInfinito := false
            SoundBeep(1000, 200) 
            try ToolTip "🛑 SEÑAL DE PARADA RECIBIDA"
            SetTimer(() => ToolTip(), -1500)
        }
    }

    EjecutarMacroLoopInfinito() {
        row := this.LV_Prog.GetNext(0)
        if (row == 0) 
            return

        ev := this.Eventos[row]
        this.MinimizarOcultar()
        
        ToolTip("🔄 LOOP INFINITO INICIADO`nPresiona " this.KeyStopLoop " para detener.", 0, 0, 1)
        SetTimer(() => ToolTip(,,,1), -4000)

        if (this.KeyStopLoop != "") {
            try Hotkey this.KeyStopLoop, this.StopLoopBinder, "On"
        }

        this.EjecutandoLoopInfinito := true
        
        Loop {
            if (!this.EjecutandoLoopInfinito || this.Pausado) {
                break
            }

            if (ev.URL != "MACRO_ONLY") {
                try Run('"' this.Navegador '" "' ev.URL '"')
                Sleep 1000
            }

            if (ev.HasOwnProp("Macros") && ev.Macros.Length > 0) {
                this.EjecutarSecuenciaMacro(ev.Macros, true) 
            } else {
                Sleep 1000 
            }
            
            Sleep 100
        }
        
        if (this.KeyStopLoop != "") {
            try Hotkey this.KeyStopLoop, "Off"
        }

        this.EjecutandoLoopInfinito := false
        this.MostrarInterfaz()
    }

    ToggleSumarUI() {
        if (!this.ChkSinHora.Value)
            this.EditOffset.Enabled := this.ChkSumar.Value
        else
            this.EditOffset.Enabled := false
    }

    ToggleSoloMacroUI() {
        this.EditURL.Enabled := !this.ChkSoloMacro.Value
    }

    AgregarProg() {
        h := this.EditHora.Text
        u := this.EditURL.Value
        
        esManual := this.ChkSinHora.Value
        if (esManual)
            h := "MANUAL"

        if (this.ChkSoloMacro.Value) {
            u := "MACRO_ONLY"
        } else {
            if (u == "") {
                ToolTip("⚠️ Falta URL")
                SetTimer(() => ToolTip(), -1500)
                return
            }
        }
        
        if (!esManual) {
            if !IsInteger(h) || StrLen(h) != 6 {
                ToolTip("⚠️ Error Hora")
                SetTimer(() => ToolTip(), -1500)
                return
            }
        }

        horaFinal := h
        if (!esManual && this.ChkSumar.Value) {
            offset := this.EditOffset.Value
            
            if (!this.EsTiempoValido(offset)) {
                ToolTip(this.T("ErrTimeRange"))
                SetTimer(() => ToolTip(), -3000)
                return
            }

            fechaBase := FormatTime(, "yyyyMMdd") . "000000"
            h_H := Integer(SubStr(h, 1, 2))
            h_M := Integer(SubStr(h, 3, 2))
            h_S := Integer(SubStr(h, 5, 2))
            fechaBase := DateAdd(fechaBase, h_H, "Hours")
            fechaBase := DateAdd(fechaBase, h_M, "Minutes")
            fechaBase := DateAdd(fechaBase, h_S, "Seconds")

            offH := Integer(SubStr(offset, 1, 2))
            offM := Integer(SubStr(offset, 3, 2))
            offS := Integer(SubStr(offset, 5, 2))
            fechaCalc := DateAdd(fechaBase, offH, "Hours")
            fechaCalc := DateAdd(fechaCalc, offM, "Minutes")
            fechaCalc := DateAdd(fechaCalc, offS, "Seconds")
            horaFinal := FormatTime(fechaCalc, "HHmmss")
        }

        nuevoEvento := {Hora: horaFinal, URL: u, Recurrente: this.ChkRecurrente.Value}

        hayMacros := false
        for m in this.TempMacroPasos {
            if IsObject(m) {
                hayMacros := true
                break
            }
        }
        if (hayMacros) {
            nuevoEvento.Macros := []
            for m in this.TempMacroPasos {
                if IsObject(m) {
                    clon := this.ParsearMacroString(this.ConstruirMacroString(m))
                    nuevoEvento.Macros.Push(clon)
                }
            }
            this.TempMacroPasos := []
            this.LimpiarPasoActual()
        }

        this.Eventos.Push(nuevoEvento)
        this.OrdenarEventos()
        this.GuardarDatos()
        this.ActualizarInterfazVisual()
        this.EditURL.Value := ""
        this.ChkRecurrente.Value := 0
        if (esManual) {
            this.ChkSinHora.Value := 0
            this.ToggleSinHora()
        }
        
        ToolTip("✅ Evento Agregado") 
        SetTimer(() => ToolTip(), -1500)
    }

    EliminarProg(row) {
        if (row == 0)
            return
        this.Eventos.RemoveAt(row)
        this.GuardarDatos()
        this.ActualizarInterfazVisual()
    }

    EliminarHistorial(row) {
        if (row == 0)
            return
        if (this.Historial.Length == 0)
            return
            
        realIdx := this.Historial.Length - row + 1
        if (realIdx >= 1 && realIdx <= this.Historial.Length) {
             this.Historial.RemoveAt(realIdx)
             this.ActualizarInterfazVisual()
             ToolTip("🗑️ Borrado")
             SetTimer(() => ToolTip(), -1000)
        }
    }

    ActualizarInterfazVisual() {
        if (this.GuiActiva == 0 || !WinExist(this.GuiActiva.Hwnd))
            return
            
        this.LV_Prog.Delete()
        this.BtnRunLoop.Enabled := false 
        
        for ev in this.Eventos {
            hFormato := ev.Hora
            if (ev.Hora == "ESPERA") {
                hFormato := "[ESPERA]"
            } 
            else if (ev.Hora != "MANUAL" && StrLen(ev.Hora)==6 && IsInteger(ev.Hora)) {
                hFormato := SubStr(ev.Hora, 1, 2) ":" SubStr(ev.Hora, 3, 2) ":" SubStr(ev.Hora, 5, 2)
            }
            
            hasM := (ev.HasOwnProp("Macros") && ev.Macros.Length > 0) ? "Sí (" ev.Macros.Length ")" : "-"
            dispUrl := (ev.URL == "MACRO_ONLY") ? "[Solo Macro]" : ev.URL
            
            if (ev.HasOwnProp("Recurrente") && ev.Recurrente == 1)
                dispUrl := "🔄 " dispUrl

            this.LV_Prog.Add(, hFormato, dispUrl, hasM)
        }

        this.LV_Hist.Delete()
        if (this.Historial.Length > 0) {
            loop this.Historial.Length {
                idx := this.Historial.Length - A_Index + 1
                item := this.Historial[idx]
                disp := (item.URL == "MACRO_ONLY") ? "[MACRO] Historial" : item.URL
                this.LV_Hist.Add(, FormatTime(item.HoraFin, "HH:mm:ss"), disp)
            }
        }

        loop 3 {
            cIdx := A_Index
            lv := this.%"LV_L" cIdx%
            lv.Opt("-Redraw")
            lv.Delete()
            loop 100
                lv.Add(, A_Index, this.Lib[cIdx][A_Index])
            lv.Opt("+Redraw")
        }
    }

    TogglePanel() {
        this.Expandido := !this.Expandido
        this.GuiActiva.Show(this.Expandido ? "w985" : "w420")
        this.BtnExp.Text := this.Expandido ? "<" : ">"
    }

    MostrarInterfazExtra() {
        this.AbrirConfigMacros(20, this.ExtraPasosData, "Configuración Extra (20 Pasos + Monitor)", true)
    }

    MinimizarOcultar() {
        if (this.GuiActiva)
            this.GuiActiva.Hide()
    }

    VerificarHorarios() {
        if (this.EnEsperaRecurrencia || this.EjecutandoLoopInfinito)
            return

        if (this.Pausado || this.EjecutandoExtra)
            return

        fechaActual := FormatTime(, "yyyyMMddHHmmss")
        indicesBorrar := []
        encontroRecurrente := false

        for i, ev in this.Eventos {
            if (ev.Hora == "MANUAL" || ev.Hora == "ESPERA")
                continue

            fechaEvento := FormatTime(, "yyyyMMdd") . ev.Hora
            
            diff := DateDiff(fechaActual, fechaEvento, "Seconds")
            
            if (diff >= 0 && diff < 300) {
                if (ev.URL != "MACRO_ONLY") {
                    try {
                        Run('"' this.Navegador '" "' ev.URL '"')
                    } catch {
                        try {
                            Run('"' ev.URL '"')
                        } catch {
                        }
                    }
                }
                if (ev.HasOwnProp("Macros") && ev.Macros.Length > 0)
                    SetTimer(this.EjecutarSecuenciaMacro.Bind(this, ev.Macros, false), -500)
                
                if (ev.HasOwnProp("Recurrente") && ev.Recurrente == 1) {
                    this.EnEsperaRecurrencia := true
                    encontroRecurrente := true
                    this.EventoCongeladoRef := ev 
                    ev.Hora := "ESPERA" 
                    
                    this.DatosEventoRecurrente := {URL: ev.URL, Recurrente: 1}
                    if (ev.HasOwnProp("Macros")) {
                        this.DatosEventoRecurrente.Macros := []
                        for m in ev.Macros {
                            this.DatosEventoRecurrente.Macros.Push(this.ParsearMacroString(this.ConstruirMacroString(m)))
                        }
                    }

                    this.ActualizarInterfazVisual()
                    SetTimer(this.AbrirVentanaRecurrencia.Bind(this), -20000) 
                } 
                else {
                    indicesBorrar.Push(i)
                }
            }
        }
        
        if (indicesBorrar.Length > 0) {
            loop indicesBorrar.Length {
                idx := indicesBorrar[indicesBorrar.Length - A_Index + 1]
                this.Eventos.RemoveAt(idx)
            }
            this.GuardarDatos()
            this.ActualizarInterfazVisual()
        }
    }

    AbrirVentanaRecurrencia() {
        SoundBeep 750, 500
        this.RecurGui := Gui("+AlwaysOnTop +Owner -Caption +Border", this.T("MsgRecurTitle"))
        this.RecurGui.SetFont("s9", "Segoe UI")
        this.RecurGui.BackColor := "White"
        
        this.RecurGui.Add("Text", "x10 y10 w220 Center", this.T("LblRecurDone"))
        this.RecurGui.Add("Text", "x10 y35 w220 Center", this.T("LblRecurAdd"))
        this.RecurEdit := this.RecurGui.Add("Edit", "x60 y80 w120 Center Number Limit6", "000000")
        
        btnOK := this.RecurGui.Add("Button", "x15 y115 w100 h30 Default", this.T("BtnRecurOK"))
        btnOK.OnEvent("Click", (*) => this.ProcesarRecurrenciaDesdeGUI())

        btnCan := this.RecurGui.Add("Button", "x125 y115 w100 h30", this.T("BtnRecurCancel"))
        btnCan.OnEvent("Click", (*) => this.CancelarRecurrencia())
        
        screenWidth := A_ScreenWidth
        guiW := 240
        targetX := screenWidth - guiW - 20
        
        this.RecurGui.Show("x" targetX " y150 w" guiW " h160 NoActivate")
    }

    ProcesarRecurrenciaDesdeGUI() {
        tiempoStr := this.RecurEdit.Value
        if (!this.EsTiempoValido(tiempoStr)) {
             ToolTip(this.T("ErrTimeRange"))
             SetTimer(() => ToolTip(), -3000)
             return
        }
        this.RecurGui.Destroy() 
        
        offset := tiempoStr
        fechaBase := FormatTime(, "yyyyMMddHHmmss")
        offH := Integer(SubStr(offset, 1, 2))
        offM := Integer(SubStr(offset, 3, 2))
        offS := Integer(SubStr(offset, 5, 2))
        fechaCalc := DateAdd(fechaBase, offH, "Hours")
        fechaCalc := DateAdd(fechaCalc, offM, "Minutes")
        fechaCalc := DateAdd(fechaCalc, offS, "Seconds")
        nuevaHora := FormatTime(fechaCalc, "HHmmss")
        
        if (this.EventoCongeladoRef != "") {
            this.EventoCongeladoRef.Hora := nuevaHora
        } else {
            nuevoEv := {Hora: nuevaHora, URL: this.DatosEventoRecurrente.URL, Recurrente: 1}
             if (this.DatosEventoRecurrente.HasOwnProp("Macros")) {
                nuevoEv.Macros := []
                for m in this.DatosEventoRecurrente.Macros
                    nuevoEv.Macros.Push(this.ParsearMacroString(this.ConstruirMacroString(m)))
            }
            this.Eventos.Push(nuevoEv)
        }

        this.OrdenarEventos()
        this.GuardarDatos()
        this.ActualizarInterfazVisual()
        
        if (this.DatosEventoRecurrente.URL != "MACRO_ONLY") {
            try {
                exeName := "ahk_exe " this.Navegador
                if WinExist(exeName) {
                    WinActivate(exeName)
                    WinWaitActive(exeName, , 2)
                    Send "^w"
                }
            } catch {
            }
        }
        
        this.EnEsperaRecurrencia := false
        this.EventoCongeladoRef := ""
        this.DatosEventoRecurrente := ""
    }

    CancelarRecurrencia() {
        this.RecurGui.Destroy()
        idxBorrar := 0
        for i, ev in this.Eventos {
            if (ev == this.EventoCongeladoRef) {
                idxBorrar := i
                break
            }
        }
        if (idxBorrar > 0)
             this.Eventos.RemoveAt(idxBorrar)

        fechaBorrar := DateAdd(A_Now, 1, "Hours")
        histItem := {
            HoraFin: A_Now, 
            URL: this.DatosEventoRecurrente.URL, 
            Caducidad: fechaBorrar
        }
        this.Historial.Push(histItem)
        if (this.Historial.Length > 200)
            this.Historial.RemoveAt(1)

        this.GuardarDatos()
        this.ActualizarInterfazVisual()
        
        if (this.DatosEventoRecurrente.URL != "MACRO_ONLY") {
            try {
                exeName := "ahk_exe " this.Navegador
                if WinExist(exeName) {
                    WinActivate(exeName)
                    WinWaitActive(exeName, , 2)
                    Send "^w"
                }
            } catch {
            }
        }

        this.EnEsperaRecurrencia := false
        this.EventoCongeladoRef := ""
        this.DatosEventoRecurrente := ""
    }

    LimpiarHistorialAuto() {
        if (this.Historial.Length == 0)
            return
        itemsToRemove := []
        ahora := A_Now
        for i, item in this.Historial {
            if (DateDiff(ahora, item.Caducidad, "Seconds") > 0)
                itemsToRemove.Push(i)
        }
        if (itemsToRemove.Length > 0) {
            loop itemsToRemove.Length {
                idx := itemsToRemove[itemsToRemove.Length - A_Index + 1]
                this.Historial.RemoveAt(idx)
            }
            this.ActualizarInterfazVisual()
        }
    }

    MonitorExtra() {
        CoordMode "Pixel", "Screen"
        CoordMode "Mouse", "Screen"
        if (!this.ExtraActivo || this.Pausado)
            return

        if (this.ExtraPasosData.Length > 0 && IsObject(this.ExtraPasosData[1])) {
            paso := this.ExtraPasosData[1]
            encontrado := false

            if (paso.HasOwnProp("ImgPath") && paso.ImgPath != "" && FileExist(paso.ImgPath)) {
                X1 := 0, Y1 := 0, X2 := A_ScreenWidth, Y2 := A_ScreenHeight
                if (paso.HasOwnProp("Zone") && paso.Zone.W > 0) {
                    X1 := paso.Zone.X, Y1 := paso.Zone.Y, X2 := paso.Zone.X + paso.Zone.W, Y2 := paso.Zone.Y + paso.Zone.H
                }
                if (ImageSearch(&fx, &fy, X1, Y1, X2, Y2, "*25 " paso.ImgPath))
                    encontrado := true
            }
            else if (paso.HasOwnProp("TargetX")) {
                encontrado := true
            }

            if (encontrado) {
                SetTimer(this.MethodMonitorExtra, 0)
                this.ExtraTimerOn := false
                this.EjecutandoExtra := true
                this.EjecutarSecuenciaMacro(this.ExtraPasosData, false)
                Sleep(this.ExtraCooldown)
                this.EjecutandoExtra := false
                if (this.ExtraActivo) {
                    SetTimer(this.MethodMonitorExtra, 10)
                    this.ExtraTimerOn := true
                }
            }
        }
    }

    EjecutarSecuenciaMacro(pasos, isInfinity := false) {
        CoordMode "Pixel", "Screen"
        CoordMode "Mouse", "Screen"
        ejecucionHabilitada := true 
        for currentIdx, paso in pasos {
            if (isInfinity && !this.EjecutandoLoopInfinito)
                return 
            if (!IsObject(paso))
                continue
            esImagen := (paso.HasOwnProp("ImgPath") && paso.ImgPath != "" && FileExist(paso.ImgPath))
            esCoord  := (!esImagen && paso.HasOwnProp("TargetX"))
            
            if (esCoord && !ejecucionHabilitada) {
                continue
            }
            tiempoBusqueda := paso.DelayBuscar
            inicio := A_TickCount
            encontrado := false
            foundX := 0, foundY := 0
            if (esImagen) {
                X1 := 0, Y1 := 0, X2 := A_ScreenWidth, Y2 := A_ScreenHeight
                if (paso.HasOwnProp("Zone") && paso.Zone.W > 0) {
                    X1 := paso.Zone.X, Y1 := paso.Zone.Y, X2 := paso.Zone.X + paso.Zone.W, Y2 := paso.Zone.Y + paso.Zone.H
                }
                Loop {
                    if (isInfinity && !this.EjecutandoLoopInfinito) 
                        return
                    if (this.Pausado) {
                        Sleep 100
                        continue
                    }
                    if (ImageSearch(&fx, &fy, X1, Y1, X2, Y2, "*25 " paso.ImgPath)) {
                        encontrado := true
                        foundX := Integer(fx + (paso.Zone.W / 2))
                        foundY := Integer(fy + (paso.Zone.H / 2))
                        break
                    }
                    if (A_TickCount - inicio > tiempoBusqueda)
                        break
                    Sleep 50
                }
                if (encontrado) {
                    ejecucionHabilitada := true
                } else {
                    ejecucionHabilitada := false
                }
                if (!encontrado && paso.HasOwnProp("SkipBlockIfFail") && paso.SkipBlockIfFail == 1)
                    continue 
            }
            else if (esCoord) {
                Sleep(tiempoBusqueda)
                if (isInfinity && !this.EjecutandoLoopInfinito)
                    return
                encontrado := true
                foundX := Integer(paso.TargetX)
                foundY := Integer(paso.TargetY)
            }
            if (encontrado) {
                Sleep(paso.DelayClick)
                if (isInfinity && !this.EjecutandoLoopInfinito)
                    return
                if (paso.HasOwnProp("NoClick") && paso.NoClick == 1)
                    continue
                baseX := foundX
                baseY := foundY
                if (paso.HasOwnProp("ClickX") && paso.ClickX > 0) {
                    baseX := Integer(paso.ClickX)
                    baseY := Integer(paso.ClickY)
                }
                rng := 0
                if (paso.HasOwnProp("Randomize") && paso.Randomize == 1) {
                    rng := 5
                    if (paso.HasOwnProp("RandomRange") && IsInteger(paso.RandomRange))
                        rng := Integer(paso.RandomRange)
                }
                if (paso.HasOwnProp("MultiClick") && paso.MultiClick == 1) {
                    intervalo := (paso.HasOwnProp("ClickInterval")) ? paso.ClickInterval : 40
                    if (paso.HasOwnProp("InfiniteLoop") && paso.InfiniteLoop == 1) {
                        Loop {
                            if (isInfinity && !this.EjecutandoLoopInfinito) 
                                return
                            if (this.Pausado) {
                                Sleep 100
                                continue
                            }
                            if GetKeyState("F3", "P") {
                                this.AlternarPausa()
                                Sleep 500
                            }
                            if (this.Pausado)
                                break
                            targetX := baseX
                            targetY := baseY
                            if (rng > 0) {
                                targetX += Random(-rng, rng)
                                targetY += Random(-rng, rng)
                            }
                            Click(targetX " " targetY)
                            Sleep(intervalo > 0 ? intervalo : 0)
                        }
                    } else {
                        duracionClicks := paso.HasOwnProp("MultiDur") ? paso.MultiDur : 1000
                        finClicks := A_TickCount + duracionClicks
                        while (A_TickCount < finClicks) {
                            if (isInfinity && !this.EjecutandoLoopInfinito) 
                                return
                            if (this.Pausado)
                                break
                            targetX := baseX
                            targetY := baseY
                            if (rng > 0) {
                                targetX += Random(-rng, rng)
                                targetY += Random(-rng, rng)
                            }
                            Click(targetX " " targetY)
                            Sleep(intervalo > 0 ? intervalo : 0)
                        }
                    }
                } else {
                    finalX := baseX
                    finalY := baseY
                    if (rng > 0) {
                        finalX += Random(-rng, rng)
                        finalY += Random(-rng, rng)
                    }
                    MouseMove(finalX, finalY)
                    Click()
                }
            }
        }
    }

    AbrirConfigMacros(maxPasos, dataArray, titulo, isExtra := false) {
        if (isExtra) {
             if (IsObject(this.GuiExtra) && this.GuiExtra != 0) {
                 try {
                     this.GuiExtra.Show()
                     return
                 } catch {
                     this.GuiExtra := 0
                 }
             }
             this.GuiExtra := Gui("Owner" this.GuiActiva.Hwnd, titulo)
             g := this.GuiExtra
        } else {
             if (IsObject(this.GuiMacros) && this.GuiMacros != 0) {
                 try {
                     this.GuiMacros.Show()
                     return
                 } catch {
                     this.GuiMacros := 0
                 }
             }
             this.GuiMacros := Gui("Owner" this.GuiActiva.Hwnd, titulo)
             g := this.GuiMacros
        }

        g.SetFont("s9", "Segoe UI")
        this.CurrentMacroArray := dataArray
        this.CurrentIsExtra := isExtra

        g.Add("Text", "x10 y10 w480", this.T("SelStepInfo"))
        g.Add("Text", "x10 y35", this.T("ListStep") " (☑ = Si falta Imagen, saltar Hijos)")
        this.LV_Pasos := g.Add("ListView", "x10 y55 w150 h400 -Multi Grid NoSort +Checked", [this.T("ColStep"), this.T("ColStatus")])
        this.LV_Pasos.ModifyCol(1, 40)
        this.LV_Pasos.ModifyCol(2, 80)
        loop maxPasos
            this.LV_Pasos.Add(, A_Index, this.T("StsEmpty"))
        this.LV_Pasos.OnEvent("ItemSelect", this.AlSeleccionarPaso.Bind(this))
        this.LV_Pasos.OnEvent("ItemCheck", this.AlMarcarPaso.Bind(this))

        g.Add("GroupBox", "x170 y45 w300 h470", this.T("GrpConfig"))
        g.SetFont("bold")
        this.LblPasoSel := g.Add("Text", "x190 y70 w260 h20 Center", this.T("SelStepPlace"))
        g.SetFont("norm")

        g.Add("Text", "x190 y100", this.T("LblType"))
        g.SetFont("bold cRed")
        this.LblEstadoImg := g.Add("Text", "x300 y100 w150", this.T("StsEmpty"))
        g.SetFont("norm cDefault")

        g.Add("Text", "x180 y130", "Sel. Área:")
        this.HKAreaSel := g.Add("Hotkey", "x240 y127 w40", this.KeyAreaSel)
        this.HKAreaSel.OnEvent("Change", (hk,*) => this.GuardarAreaKey(hk.Value))

        g.Add("Text", "x295 y130", "Mouse:")
        this.HKEditor := g.Add("Hotkey", "x345 y127 w40", this.CaptureKey)
        this.HKEditor.OnEvent("Change", (hk,*) => this.GuardarHotkey(hk.Value))

        g.Add("Text", "x180 y160", "Tecla FOTO:")
        this.HKMacroFoto := g.Add("Hotkey", "x255 y157 w40", this.KeyMacroFoto)
        this.HKMacroFoto.OnEvent("Change", (*) => this.UpdateDynamicHotkeys())

        g.Add("Text", "x305 y160", "COORD:")
        this.HKMacroCoord := g.Add("Hotkey", "x355 y157 w40", this.KeyMacroCoord)
        this.HKMacroCoord.OnEvent("Change", (*) => this.UpdateDynamicHotkeys())

        this.BtnCapturar := g.Add("Button", "x190 y190 w125 h35", this.T("BtnFoto"))
        this.BtnCapturar.OnEvent("Click", (*) => this.CapturarPasoActual())
        this.BtnCapturar.Enabled := false

        this.BtnCapCoord := g.Add("Button", "x325 y190 w125 h35", this.T("BtnCoord"))
        this.BtnCapCoord.OnEvent("Click", (*) => this.CapturarCoordenadasPaso())
        this.BtnCapCoord.Enabled := false

        g.Add("Text", "x190 y235", this.T("LblSearch"))
        this.EdDelayBus := g.Add("Edit", "x190 y255 w260 Number", "1400")
        this.EdDelayBus.Enabled := false
        this.EdDelayBus.OnEvent("Change", (*) => this.GuardarCambioEnMemoria())

        g.Add("Text", "x190 y285", this.T("LblPreClick"))
        this.EdDelayClk := g.Add("Edit", "x190 y305 w260 Number", "1400")
        this.EdDelayClk.Enabled := false
        this.EdDelayClk.OnEvent("Change", (*) => this.GuardarCambioEnMemoria())

        this.ChkNoClick := g.Add("Checkbox", "x190 y335 w260", "👁️ Solo Detectar (No Click)")
        this.ChkNoClick.Enabled := false
        this.ChkNoClick.OnEvent("Click", (*) => this.GuardarCambioEnMemoria())

        this.ChkRandom := g.Add("Checkbox", "x190 y360 w80", "🎲 Random")
        this.ChkRandom.Enabled := false
        this.ChkRandom.OnEvent("Click", (*) => this.GuardarCambioEnMemoria())

        this.EdRandomRange := g.Add("Edit", "x280 y358 w50 Number", "5")
        this.EdRandomRange.Enabled := false
        this.EdRandomRange.OnEvent("Change", (*) => this.GuardarCambioEnMemoria())
        g.Add("Text", "x340 y361", "px")

        this.ChkMultiClick := g.Add("Checkbox", "x190 y395 w260", this.T("ChkTurbo"))
        this.ChkMultiClick.Enabled := false
        this.ChkMultiClick.OnEvent("Click", (*) => this.ToggleMultiClickUI())

        g.Add("Text", "x190 y420", this.T("LblDur"))
        this.EdMultiDur := g.Add("Edit", "x190 y440 w120 Number", "1000")
        this.EdMultiDur.Enabled := false
        this.EdMultiDur.OnEvent("Change", (*) => this.GuardarCambioEnMemoria())

        g.Add("Text", "x320 y420", "Intervalo (ms):")
        this.EdInterval := g.Add("Edit", "x320 y440 w60 Number", "40")
        this.EdInterval.Enabled := false
        this.EdInterval.OnEvent("Change", (*) => this.GuardarCambioEnMemoria())

        this.ChkLoop := g.Add("Checkbox", "x390 y440 w60", "∞ Bucle")
        this.ChkLoop.Enabled := false
        this.ChkLoop.OnEvent("Click", (*) => this.GuardarCambioEnMemoria())

        this.LblClickCoords := g.Add("Text", "x190 y470 w260 cBlue", this.T("LblCoordInfo"))
        g.SetFont("s8")
        this.LblClickCoords.SetFont("s8")

        if (isExtra) {
            g.SetFont("s9")
            g.Add("Text", "x190 y490", "Cooldown Final (ms):")
            this.EdExtraCool := g.Add("Edit", "x320 y488 w130 Number", this.ExtraCooldown)
            this.EdExtraCool.OnEvent("Change", (*) => this.ExtraCooldown := this.EdExtraCool.Value)
        }

        g.SetFont("s9")
        g.Add("Button", "x10 y530 w150 h35 Default", this.T("BtnSave")).OnEvent("Click", (*) => this.FinalizarConfig(g, isExtra))
        g.Add("Button", "x170 y530 w100 h35", this.T("BtnClean")).OnEvent("Click", (*) => this.LimpiarPasoActual())

        txtManual := isExtra ? this.T("ManExtraTitle") : this.T("ManMacroTitle")
        txtBody := isExtra ? this.T("ManExtraText") : this.T("ManMacroText")
        g.Add("Button", "x380 y535 w90 h25", this.T("BtnManual")).OnEvent("Click", (*) => this.AbrirManualPersonalizado(txtManual, txtBody))

        if (isExtra) {
            txtBtn := this.ExtraActivo ? this.T("BtnMonOff") : this.T("BtnMonOn")
            optBtn := this.ExtraActivo ? "cRed" : "cGreen"
            g.SetFont("bold " optBtn)
            this.BtnToggleExtra := g.Add("Button", "x275 y530 w100 h35", txtBtn)
            g.SetFont("norm cDefault")
            this.BtnToggleExtra.OnEvent("Click", (*) => this.ToggleExtraMonitor())
        }

        this.RefrescarListView(maxPasos)

        WinGetPos(&mX, &mY, &mW, &mH, this.GuiActiva.Hwnd)
        gW := 490, gH := 600
        newX := mX + (mW - gW) / 2
        newY := mY + (mH - gH) / 2

        this.RegisterMacroHotkeys(true)
        g.Show("x" newX " y" newY " w" gW " h" gH)
        g.OnEvent("Close", (*) => this.FinalizarConfig(g, isExtra, true))
    }

    AlMarcarPaso(lv, item, checked) {
        this.PrepararObjPaso(item)
        if (this.CurrentMacroArray.Has(item) && IsObject(this.CurrentMacroArray[item])) {
            this.CurrentMacroArray[item].SkipBlockIfFail := checked
        }
    }

    RegisterMacroHotkeys(enable) {
        HotIf (*) => this.IsConfigOpen()
        if (enable) {
            if (this.KeyMacroFoto != "")
                Hotkey this.KeyMacroFoto, (*) => this.TriggerMacroAction("FOTO"), "On"
            if (this.KeyMacroCoord != "")
                Hotkey this.KeyMacroCoord, (*) => this.TriggerMacroAction("COORD"), "On"
        } else {
            try Hotkey this.KeyMacroFoto, "Off"
            try Hotkey this.KeyMacroCoord, "Off"
        }
    }

    UpdateDynamicHotkeys() {
        try Hotkey this.KeyMacroFoto, "Off"
        try Hotkey this.KeyMacroCoord, "Off"
        this.KeyMacroFoto := this.HKMacroFoto.Value
        this.KeyMacroCoord := this.HKMacroCoord.Value
        this.RegisterMacroHotkeys(true)
        this.GuardarDatos()
    }

    GuardarAreaKey(val) {
        if (val != "") {
            this.KeyAreaSel := val
            this.GuardarDatos()
        }
    }

    TriggerMacroAction(tipo) {
        if (this.IsEditingText()) {
            Send(A_ThisHotkey)
            return
        }
        if (tipo == "FOTO")
            this.CapturarPasoActual()
        else
            this.CapturarCoordenadasPaso()
    }

    AlSeleccionarPaso(lv, item, selected) {
        if (!selected)
            return
        this.CurrentStepIndex := item
        try {
            this.LblPasoSel.Text := this.T("ColStep") " #" item
            this.BtnCapturar.Enabled := true
            this.BtnCapCoord.Enabled := true
            this.EdDelayBus.Enabled := true
            this.EdDelayClk.Enabled := true
            this.ChkMultiClick.Enabled := true
            this.ChkNoClick.Enabled := true
            this.ChkRandom.Enabled := true
            this.EdRandomRange.Enabled := true

            if (this.CurrentMacroArray.Has(item) && IsObject(this.CurrentMacroArray[item])) {
                data := this.CurrentMacroArray[item]
                if (data.HasOwnProp("ImgPath") && data.ImgPath != "") {
                    this.LblEstadoImg.Text := this.T("StsImg")
                    this.LblEstadoImg.Opt("cGreen")
                } else if (data.HasOwnProp("TargetX")) {
                    this.LblEstadoImg.Text := this.T("StsCoord")
                    this.LblEstadoImg.Opt("cBlue")
                } else {
                    this.LblEstadoImg.Text := this.T("StsEmpty")
                    this.LblEstadoImg.Opt("cRed")
                }
                this.EdDelayBus.Value := data.DelayBuscar
                this.EdDelayClk.Value := data.DelayClick

                this.ChkNoClick.Value := (data.HasOwnProp("NoClick") ? data.NoClick : 0)
                this.ChkRandom.Value := (data.HasOwnProp("Randomize") ? data.Randomize : 0)
                this.EdRandomRange.Value := (data.HasOwnProp("RandomRange") ? data.RandomRange : 5)

                if (data.HasOwnProp("MultiClick") && data.MultiClick == 1) {
                    this.ChkMultiClick.Value := 1
                    this.EdMultiDur.Value := data.HasOwnProp("MultiDur") ? data.MultiDur : 1000
                    this.EdInterval.Value := data.HasOwnProp("ClickInterval") ? data.ClickInterval : 40
                    this.ChkLoop.Value := data.HasOwnProp("InfiniteLoop") ? data.InfiniteLoop : 0
                    if (data.HasOwnProp("ClickX") && data.ClickX > 0)
                        this.LblClickCoords.Text := "Coord: " data.ClickX "," data.ClickY
                    else
                        this.LblClickCoords.Text := this.T("LblCoordInfo")
                } else {
                    this.ChkMultiClick.Value := 0
                    this.EdMultiDur.Value := 1000
                    this.EdInterval.Value := 40
                    this.ChkLoop.Value := 0
                    this.LblClickCoords.Text := this.T("LblCoordInfo")
                }
            } else {
                this.LblEstadoImg.Text := this.T("StsEmpty")
                this.LblEstadoImg.Opt("cRed")
                this.EdDelayBus.Value := 1400
                this.EdDelayClk.Value := 1400
                this.ChkMultiClick.Value := 0
                this.ChkNoClick.Value := 0
                this.ChkRandom.Value := 0
                this.EdRandomRange.Value := 5
                this.EdMultiDur.Value := 1000
                this.EdInterval.Value := 40
                this.ChkLoop.Value := 0
                this.LblClickCoords.Text := this.T("LblCoordInfo")
            }
            this.ToggleMultiClickUI()
        } catch {
        }
    }

    ToggleMultiClickUI() {
        try {
            isMulti := this.ChkMultiClick.Value
            this.EdMultiDur.Enabled := isMulti
            this.EdInterval.Enabled := isMulti
            this.ChkLoop.Enabled := isMulti
            this.GuardarCambioEnMemoria()
        } catch {
        }
    }

    CapturarPasoActual() {
        if (this.CurrentStepIndex == 0)
            return
        this.OcultarTodasGUI()
        Sleep 200
        area := this.SelectArea()
        if (area.w > 0) {
            prefix := (this.CurrentIsExtra) ? "Extra_" : "Macro_"
            fName := "Capturas\" prefix FormatTime(,"yyyyMMddHHmmss") "_" this.CurrentStepIndex ".png"
            this.CaptureScreen(area.x, area.y, area.w, area.h, fName)
            this.PrepararObjPaso(this.CurrentStepIndex)
            obj := this.CurrentMacroArray[this.CurrentStepIndex]
            obj.ImgPath := fName
            obj.Zone := area
            if obj.HasOwnProp("TargetX")
                obj.DeleteProp("TargetX")
            this.ActualizarDatosUI(obj)
            try {
                this.LblEstadoImg.Text := this.T("StsImg")
                this.LblEstadoImg.Opt("cGreen")
                this.RefrescarListView(this.CurrentMacroArray.Length > 100 ? this.CurrentMacroArray.Length : 100)
            } catch {
            }
        }
        this.MostrarTodasGUI()
    }

    CapturarCoordenadasPaso() {
        if (this.CurrentStepIndex == 0)
            return
        this.OcultarTodasGUI()
        CoordMode "Mouse", "Screen"
        ToolTip(this.T("TipCoord") " " this.CaptureKey)
        KeyWait this.CaptureKey, "D"
        MouseGetPos &tx, &ty
        ToolTip()
        this.PrepararObjPaso(this.CurrentStepIndex)
        obj := this.CurrentMacroArray[this.CurrentStepIndex]
        obj.ImgPath := ""
        obj.Zone := {x:0, y:0, w:0, h:0}
        obj.TargetX := tx
        obj.TargetY := ty
        this.ActualizarDatosUI(obj)
        try {
            this.LblEstadoImg.Text := this.T("StsCoord")
            this.LblEstadoImg.Opt("cBlue")
            this.RefrescarListView(this.CurrentMacroArray.Length > 100 ? this.CurrentMacroArray.Length : 100)
            this.LblClickCoords.Text := this.T("LblCoordInfo")
        } catch {
        }
        Sleep 200
        this.MostrarTodasGUI()
    }

    PrepararObjPaso(idx) {
        while (this.CurrentMacroArray.Length < idx)
            this.CurrentMacroArray.Push("")
        if (!IsObject(this.CurrentMacroArray[idx]))
            this.CurrentMacroArray[idx] := {ImgPath: "", MultiClick: 0, MultiDur: 1000, NoClick: 0, SkipBlockIfFail: 0}
        else {
            if !this.CurrentMacroArray[idx].HasOwnProp("SkipBlockIfFail")
                this.CurrentMacroArray[idx].SkipBlockIfFail := 0
            if !this.CurrentMacroArray[idx].HasOwnProp("ImgPath")
                this.CurrentMacroArray[idx].ImgPath := ""
        }
    }

    ActualizarDatosUI(obj) {
        valB := ""
        valC := ""
        try {
            if (this.EdDelayBus)
                valB := this.EdDelayBus.Value
            if (this.EdDelayClk)
                valC := this.EdDelayClk.Value
        } catch {
        }
        if (valB == "")
            valB := 1400
        if (valC == "")
            valC := 1400
        obj.DelayBuscar := valB
        obj.DelayClick := valC
    }

    GuardarCambioEnMemoria() {
        idx := this.CurrentStepIndex
        if (idx > 0 && this.CurrentMacroArray.Has(idx) && IsObject(this.CurrentMacroArray[idx])) {
            try {
                this.CurrentMacroArray[idx].DelayBuscar := this.EdDelayBus.Value
                this.CurrentMacroArray[idx].DelayClick := this.EdDelayClk.Value
                this.CurrentMacroArray[idx].MultiClick := this.ChkMultiClick.Value
                this.CurrentMacroArray[idx].MultiDur := this.EdMultiDur.Value
                this.CurrentMacroArray[idx].NoClick := this.ChkNoClick.Value
                this.CurrentMacroArray[idx].Randomize := this.ChkRandom.Value
                this.CurrentMacroArray[idx].RandomRange := this.EdRandomRange.Value
                this.CurrentMacroArray[idx].ClickInterval := this.EdInterval.Value
                this.CurrentMacroArray[idx].InfiniteLoop := this.ChkLoop.Value
            } catch {
            }
        }
    }

    LimpiarPasoActual() {
        idx := this.CurrentStepIndex
        if (idx > 0 && this.CurrentMacroArray.Has(idx))
            this.CurrentMacroArray[idx] := ""
        try {
            this.LblEstadoImg.Text := this.T("StsEmpty")
            this.LblEstadoImg.Opt("cRed")
            this.EdDelayBus.Value := 1400
            this.EdDelayClk.Value := 1400
            this.ChkMultiClick.Value := 0
            this.ChkNoClick.Value := 0
            this.ChkRandom.Value := 0
            this.EdRandomRange.Value := 5
            this.EdMultiDur.Value := 1000
            this.EdInterval.Value := 40
            this.ChkLoop.Value := 0
            this.ToggleMultiClickUI()
            this.LV_Pasos.Modify(idx, "-Check", , this.T("StsEmpty"))
            this.RefrescarListView(this.CurrentMacroArray.Length > 100 ? this.CurrentMacroArray.Length : 100)
        } catch {
        }
    }

    FinalizarConfig(g, isExtra, closed := false) {
        this.RegisterMacroHotkeys(false)
        if (isExtra && !closed) {
            this.GuardarExtraDatosDisk()
            ToolTip("💾 Guardado", 0, 0, 3)
            SetTimer(() => ToolTip( , , , 3), -1000)
        }
        if (!closed)
            g.Destroy()
        if (isExtra)
            this.GuiExtra := 0
        else
            this.GuiMacros := 0
        if (this.GuiActiva)
            this.GuiActiva.Opt("-Disabled")
    }

    RefrescarListView(maxPasos) {
        this.LV_Pasos.Delete()
        ultimoFueImagen := false
        loop maxPasos {
            status := this.T("StsEmpty")
            isChecked := 0
            if (this.CurrentMacroArray.Has(A_Index) && IsObject(this.CurrentMacroArray[A_Index])) {
                item := this.CurrentMacroArray[A_Index]
                isImg := (item.HasOwnProp("ImgPath") && item.ImgPath != "")
                isCoord := (item.HasOwnProp("TargetX"))
                if (isImg) {
                    status := "📷 " this.T("StsImg")
                    ultimoFueImagen := true 
                } 
                else if (isCoord) {
                    if (ultimoFueImagen) {
                        status := "   └─ 📍 " this.T("StsCoord")
                    } else {
                        status := "📍 " this.T("StsCoord")
                    }
                } else {
                    ultimoFueImagen := false 
                }
                if (item.HasOwnProp("SkipBlockIfFail") && item.SkipBlockIfFail == 1)
                    isChecked := 1
            } else {
                ultimoFueImagen := false
            }
            opciones := (isChecked ? "Check" : "-Check")
            this.LV_Pasos.Add(opciones, A_Index, status)
        }
    }

    OcultarTodasGUI() {
        if (this.GuiActiva) {
            this.GuiActiva.Hide()
        }
        if (this.GuiMacros) {
            this.GuiMacros.Hide()
        }
        if (this.GuiExtra) {
            this.GuiExtra.Hide()
        }
    }

    MostrarTodasGUI() {
        if (this.GuiActiva) {
            this.GuiActiva.Show()
        }
        if (this.CurrentIsExtra) {
            if (this.GuiExtra) {
                this.GuiExtra.Show()
            }
        } else {
            if (this.GuiMacros) {
                this.GuiMacros.Show()
            }
        }
    }

    ; ==========================================================================
    ; SECCIÓN 5: OTROS
    ; ==========================================================================
    GuardarHotkey(val) {
        if (val != "") {
            this.CaptureKey := val
            this.GuardarDatos()
        }
    }

    AbrirManualPersonalizado(titulo, texto) {
        mGui := Gui("+Owner" this.GuiActiva.Hwnd, titulo)
        mGui.BackColor := "White"
        mGui.SetFont("s10", "Arial")
        ed := mGui.Add("Edit", "x10 y10 w480 h300 ReadOnly -E0x200", texto)
        btnOK := mGui.Add("Button", "x200 y320 w100 h30 Default", "OK")
        btnOK.OnEvent("Click", (*) => mGui.Destroy())
        mGui.Show("w500 h360")
        btnOK.Focus()
    }

    CambiarIdiomaMenu() {
        m := Menu()
        m.Add("Español (MX)", (*) => this.SetIdioma("ES"))
        m.Add("English (USA)", (*) => this.SetIdioma("EN"))
        m.Add("Português (BR)", (*) => this.SetIdioma("PT"))
        m.Add("Bahasa Indonesia", (*) => this.SetIdioma("ID"))
        m.Show()
    }

    SetIdioma(code) {
        this.Idioma := code
        this.GuardarDatos()
        Reload()
    }

    MostrarAyuda() {
        MsgBox(this.T("MsgHelp"), this.T("BtnHelp"))
    }

    ClickLib(lv, rowNum) {
        if (rowNum == 0)
            return
        colIdx := (lv = this.LV_L1) ? 1 : (lv = this.LV_L2) ? 2 : 3
        url := this.Lib[colIdx][rowNum]
        if (url != "") {
            try {
                Run('"' this.Navegador '" "' url '"')
            } catch {
                Run('"' url '"')
            }
        }
    }

    EditLib(lv, rowNum) {
        if (rowNum == 0)
            return
        colIdx := (lv = this.LV_L1) ? 1 : (lv = this.LV_L2) ? 2 : 3
        actual := this.Lib[colIdx][rowNum]
        res := InputBox("URL:", "Editar", , actual)
        if (res.Result == "OK") {
            this.Lib[colIdx][rowNum] := res.Value
            this.GuardarDatos()
            this.ActualizarInterfazVisual()
        }
    }

    MenuLib(lv, rowNum) {
        colIdx := (lv = this.LV_L1) ? 1 : (lv = this.LV_L2) ? 2 : 3
        m := Menu()
        if (rowNum > 0)
            m.Add("Borrar Link", (*) => this.BorrarLib(colIdx, rowNum))
        m.Show()
    }

    BorrarLib(c, r) {
        this.Lib[c][r] := ""
        this.GuardarDatos()
        this.ActualizarInterfazVisual()
    }

    CambiarNav(n) {
        this.Navegador := this.OpcionesNav[n]
        this.GuardarDatos()
    }

    AlternarPausa() {
        this.Pausado := !this.Pausado
        ToolTip("SCRIPT " (this.Pausado ? "PAUSADO" : "ACTIVO"))
        SetTimer(() => ToolTip(), -2000)
    }

    VerEventosMouse() {
        t := "PRÓXIMOS:`n"
        for ev in this.Eventos
            t .= ev.URL "`n"
        ToolTip(t)
        SetTimer(() => ToolTip(), -5000)
    }

    ToggleExtraMonitor() {
        this.ExtraActivo := !this.ExtraActivo
        if (!this.HasOwnProp("MethodMonitorExtra"))
            this.MethodMonitorExtra := this.MonitorExtra.Bind(this)

        if (this.ExtraActivo) {
            SetTimer(this.MethodMonitorExtra, 10)
            this.ExtraTimerOn := true
            MsgBox("Monitor ON", "Info", "T1")
        } else {
            SetTimer(this.MethodMonitorExtra, 0)
            this.ExtraTimerOn := false
            MsgBox("Monitor OFF", "Info", "T1")
        }

        if (this.GuiExtra && WinExist(this.GuiExtra.Hwnd)) {
             this.BtnToggleExtra.Text := this.ExtraActivo ? this.T("BtnMonOff") : this.T("BtnMonOn")
             opt := this.ExtraActivo ? "cRed" : "cGreen"
             this.GuiExtra.SetFont("bold " opt)
             this.BtnToggleExtra.SetFont("bold " opt)
        }
    }

    SelectArea() {
        area := {x:0, y:0, w:0, h:0}
        SelGui := Gui("-Caption +AlwaysOnTop +ToolWindow +LastFound")
        SelGui.BackColor := "Black"
        WinSetTransparent(50, SelGui)
        SelGui.Show("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight)
        CoordMode "Mouse", "Screen"
        ToolTip("MANTÉN PRESIONADA '" this.KeyAreaSel "'`nEn la esquina inicial, arrastra y suelta en la final.")
        KeyWait this.KeyAreaSel, "D"
        MouseGetPos &x1, &y1
        KeyWait this.KeyAreaSel
        MouseGetPos &x2, &y2
        ToolTip()
        SelGui.Destroy()
        area.x := Min(x1, x2)
        area.y := Min(y1, y2)
        area.w := Abs(x2 - x1)
        area.h := Abs(y2 - y1)
        return area
    }

    CaptureScreen(x, y, w, h, filename) {
        pBitmap := this.GDI.CreateBitmapFromScreen(x, y, w, h)
        this.GDI.SaveBitmapToFile(pBitmap, filename)
        this.GDI.DisposeImage(pBitmap)
    }
}
