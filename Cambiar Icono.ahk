#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; GUI PRINCIPAL
; ==============================================================================
App := Gui(, "Cambiador de Iconos Pro")
App.SetFont("s9", "Segoe UI")

App.Add("GroupBox", "x10 y10 w400 h130", "Archivos")

App.Add("Text", "x20 y35", "Selecciona el Ejecutable (.exe):")
EditExe := App.Add("Edit", "x20 y55 w300 ReadOnly")
App.Add("Button", "x330 y54 w70", "Buscar").OnEvent("Click", (*) => SeleccionarArchivo(EditExe, "exe"))

App.Add("Text", "x20 y90", "Selecciona el Icono (.ico):")
EditIco := App.Add("Edit", "x20 y110 w300 ReadOnly")
App.Add("Button", "x330 y109 w70", "Buscar").OnEvent("Click", (*) => SeleccionarArchivo(EditIco, "ico"))

BtnCambiar := App.Add("Button", "x10 y150 w400 h40", "CAMBIAR ICONO")
BtnCambiar.OnEvent("Click", EjecutarCambio)
BtnCambiar.SetFont("bold")

App.OnEvent("Close", (*) => ExitApp())
App.Show()

SeleccionarArchivo(ctrlEdit, ext) {
    path := FileSelect(3, , "Seleccionar " ext, "*." ext)
    if (path != "")
        ctrlEdit.Value := path
}

EjecutarCambio(*) {
    exePath := EditExe.Value
    icoPath := EditIco.Value
    
    if (exePath = "" || icoPath = "") {
        MsgBox("Por favor selecciona ambos archivos.", "Error", 16)
        return
    }
    
    ; 1. Crear Backup de seguridad
    backupPath := exePath ".bak"
    try {
        FileCopy(exePath, backupPath, 1)
    } catch as err {
        MsgBox("No se pudo crear el backup (Permisos o archivo en uso).`nError: " err.Message, "Error", 16)
        return
    }
    
    ; 2. Intentar cambiar el icono
    try {
        Result := IconChanger.InjectIcon(exePath, icoPath)
        if (Result)
            MsgBox("¡Icono cambiado con ÉXITO!`n`nSe ha creado un backup del original en la misma carpeta.", "Éxito", 64)
        else
            MsgBox("No se pudo actualizar el recurso del EXE. Es posible que esté comprimido o protegido.", "Error", 16)
    } catch as err {
        MsgBox("Ocurrió un error crítico durante la inyección:`n" err.Message, "Error Fatal", 16)
        ; Intentar restaurar backup si falló
        try FileMove(backupPath, exePath, 1)
    }
}

; ==============================================================================
; CLASE PROFESIONAL PARA MANIPULACIÓN DE RECURSOS PE (Portable Executable)
; ==============================================================================
class IconChanger {
    
    static InjectIcon(exeFile, icoFile) {
        ; 1. LEER EL ARCHIVO .ICO COMPLETO A MEMORIA
        bufIco := FileRead(icoFile, "RAW")
        
        ; 2. ANALIZAR CABECERA ICO (6 bytes)
        ; Offset 0 (2 bytes): Reservado (0)
        ; Offset 2 (2 bytes): Tipo (1 para ICO)
        ; Offset 4 (2 bytes): Cantidad de imágenes
        if (bufIco.Size < 6 || NumGet(bufIco, 2, "UShort") != 1)
            throw Error("El archivo seleccionado no es un ICO válido.")
            
        imgCount := NumGet(bufIco, 4, "UShort")
        
        ; 3. INICIAR ACTUALIZACIÓN DE RECURSOS EN EL EXE
        ; hUpdate devuelve un handle si tiene éxito. False si falla.
        hUpdate := DllCall("kernel32\BeginUpdateResource", "WStr", exeFile, "Int", 0, "Ptr")
        if !hUpdate
            throw Error("No se pudo abrir el EXE para escritura (BeginUpdateResource).")
            
        try {
            ; Estructura GRPICONDIR para el EXE (Header + Entries)
            ; Header (6 bytes) + (14 bytes * imgCount)
            grpSize := 6 + (14 * imgCount)
            grpBuf := Buffer(grpSize, 0)
            
            ; Escribir Header en el grupo
            NumPut("UShort", 0, grpBuf, 0) ; Reserved
            NumPut("UShort", 1, grpBuf, 2) ; Type (1 = Icon)
            NumPut("UShort", imgCount, grpBuf, 4) ; Count
            
            ; 4. PROCESAR CADA IMAGEN DENTRO DEL ICO
            Loop imgCount {
                i := A_Index - 1
                
                ; Offset de la entrada en el archivo ICO (6 header + 16 * i)
                icoEntryOffset := 6 + (16 * i)
                
                ; Leer datos de la entrada del archivo ICO
                w := NumGet(bufIco, icoEntryOffset + 0, "UChar")
                h := NumGet(bufIco, icoEntryOffset + 1, "UChar")
                colors := NumGet(bufIco, icoEntryOffset + 2, "UChar")
                reserved := NumGet(bufIco, icoEntryOffset + 3, "UChar")
                planes := NumGet(bufIco, icoEntryOffset + 4, "UShort")
                bitCount := NumGet(bufIco, icoEntryOffset + 6, "UShort")
                bytesInRes := NumGet(bufIco, icoEntryOffset + 8, "UInt")
                dataOffset := NumGet(bufIco, icoEntryOffset + 12, "UInt")
                
                ; ID del Icono Individual (Usamos índices secuenciales 1, 2, 3...)
                nID := A_Index 
                
                ; Extraer los datos RAW de la imagen (PNG o BMP) del buffer del archivo
                imgData := Buffer(bytesInRes)
                DllCall("RtlMoveMemory", "Ptr", imgData.Ptr, "Ptr", bufIco.Ptr + dataOffset, "UPtr", bytesInRes)
                
                ; Actualizar el Recurso RT_ICON (Tipo 3)
                ; UpdateResource(hUpdate, RT_ICON, MAKEINTRESOURCE(nID), LANG_NEUTRAL, data, size)
                ret := DllCall("kernel32\UpdateResource", "Ptr", hUpdate, "Ptr", 3, "Ptr", nID, "UShort", 1033, "Ptr", imgData.Ptr, "UInt", bytesInRes, "Int")
                if !ret
                    throw Error("Fallo al actualizar el icono individual ID: " nID)
                
                ; 5. CONSTRUIR ENTRADA PARA EL GRPICONDIR (Estructura diferente al ICO)
                ; GRPICONDIRENTRY es 14 bytes (no tiene el offset de archivo, tiene el ID)
                grpEntryOffset := 6 + (14 * i)
                NumPut("UChar", w, grpBuf, grpEntryOffset + 0)
                NumPut("UChar", h, grpBuf, grpEntryOffset + 1)
                NumPut("UChar", colors, grpBuf, grpEntryOffset + 2)
                NumPut("UChar", reserved, grpBuf, grpEntryOffset + 3)
                NumPut("UShort", planes, grpBuf, grpEntryOffset + 4)
                NumPut("UShort", bitCount, grpBuf, grpEntryOffset + 6)
                NumPut("UInt", bytesInRes, grpBuf, grpEntryOffset + 8)
                NumPut("UShort", nID, grpBuf, grpEntryOffset + 12) ; Aquí va el ID en lugar del offset
            }
            
            ; 6. ACTUALIZAR EL GRUPO DE ICONOS (RT_GROUP_ICON = 14)
            ; Usamos ID 1 para el icono principal (Estándar en Windows) o 159 para AHK Scripts.
            ; Intentaremos reemplazar el ID 1 primero, que es lo común en apps genéricas.
            ; Nota: Para scripts compilados de AHK el ID suele ser 159, pero Windows prioriza alfabéticamente/numéricamente.
            ; Forzaremos el ID 159 (AHK) y el ID 1 (Genérico) para asegurar el cambio.
            
            ; Actualizar ID 1 (Genérico)
            DllCall("kernel32\UpdateResource", "Ptr", hUpdate, "Ptr", 14, "Ptr", 1, "UShort", 1033, "Ptr", grpBuf.Ptr, "UInt", grpSize, "Int")
            
            ; Actualizar ID 159 (Específico AutoHotkey / AutoIt)
            DllCall("kernel32\UpdateResource", "Ptr", hUpdate, "Ptr", 14, "Ptr", 159, "UShort", 1033, "Ptr", grpBuf.Ptr, "UInt", grpSize, "Int")
            
            ; 7. FINALIZAR Y GUARDAR
            ; EndUpdateResource(hUpdate, fDiscard) -> fDiscard = 0 para guardar
            if !DllCall("kernel32\EndUpdateResource", "Ptr", hUpdate, "Int", 0, "Int")
                throw Error("No se pudo guardar el archivo final.")
                
            return true
            
        } catch as e {
            ; Si algo falla, descartar cambios
            DllCall("kernel32\EndUpdateResource", "Ptr", hUpdate, "Int", 1, "Int")
            throw e
        }
    }
}
