<#
.SYNOPSIS
Skript, mit dem ich unerwünschte Dateien löschen kann

.DESCRIPTION
Dieses Skript wird nach dem Neustart des Servers ausgeführt
und löscht alle Dateien aus dem Azure-Verzeichnis,
die nicht mehr verwendet werden und nicht mehr benötigt werden.

.PARAMETER repertoire
Pfad zum Verzeichnis, das die zu löschenden Dateien enthält.

.PARAMETER extension
Die Erweiterung der zu löschenden Datei

.NOTES
Auteur : A. Eggenschwiler
Date : 14.08.2025

.LINK
https://modan.ch
#>

$AgentsRoot = "C:\AzureDevOpsAgents"  # Chemin vers vos agents
$LogFolder = "C:\LOGAgentDelet"
$LogFile = "$LogFolder\cleanup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"  # Fichier de log

# === FONCTIONS ===
function Write-Log {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $Message"
    Write-Host $Message -ForegroundColor $Color
    
    # Créer le dossier du fichier de log si nécessaire
    $logDir = Split-Path $LogFile -Parent
    if ($logDir -and -not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    $logMessage | Out-File -FilePath $LogFile -Append -Encoding utf8
}

# === CONDITION HORAIRE (23h00-01h00) ===
$now   = Get-Date
$start = [datetime]::Today.AddHours(23)   # 23h
$end   = [datetime]::Today.AddDays(1).AddHours(1) #1h du matin

if ($now -lt $start -or $now -ge $end) {
    Write-Log "Script ignoré : hors de la fenêtre horaire (02h00-03h00)." "Yellow"
    exit 0
}

# Fonction robuste de suppression pour éviter "directory is not empty"
function Remove-FolderRobust {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $true
    }

    Write-Log "Suppression : $Path" "Cyan"
    
    # Supprimer les attributs en lecture seule récursivement
    try {
        Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReadOnly } |
            ForEach-Object { 
                try {
                    $_.Attributes = $_.Attributes -band -bnot [System.IO.FileAttributes]::ReadOnly 
                } catch {
                    # Ignorer les erreurs d'attributs
                }
            }
    } catch {
        # Ignorer les erreurs de parcours
    }

    # Tentatives multiples avec PowerShell
    $maxAttempts = 3
    for ($i = 1; $i -le $maxAttempts; $i++) {
        try {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            Write-Log " Suppression réussie (tentative $i)" "Green"
            return $true
        } catch {
            Write-Log " Tentative $i échouée: $($_.Exception.Message)" "Yellow"
            if ($i -lt $maxAttempts) {
                Start-Sleep -Seconds 2
            }
        }
    }

    # Dernière tentative avec rmdir (plus fiable pour les gros volumes)
    try {
        Write-Log " → Tentative finale avec rmdir..." "Yellow"
        cmd.exe /c "rmdir /s /q `"$Path`"" 2>$null
        
        if (-not (Test-Path $Path)) {
            Write-Log "  Suppression réussie avec rmdir" "Green"
            return $true
        } else {
            Write-Log "  Échec final - dossier toujours présent" "Red"
        }
    } catch {
        Write-Log "  Échec final avec rmdir: $($_.Exception.Message)" "Red"
    }

    return $false
}

# === SCRIPT PRINCIPAL ===
# Vérification du chemin racine
if (-not (Test-Path $AgentsRoot)) {
    Write-Log "ERREUR: Le chemin AgentsRoot '$AgentsRoot' n'existe pas." "Red"
    Write-Log "Veuillez modifier la variable `$AgentsRoot dans ce script." "Yellow"
    exit 1
}

# Initialisation
Write-Log "=== Début du nettoyage des dossiers de build ===" "Magenta"
Write-Log "Racine des agents: $AgentsRoot" "Gray"
Write-Log "Fichier de log: $LogFile" "Gray"

try {
    # Trouver tous les sous-dossiers contenant _work
    $agentWorkFolders = Get-ChildItem -Path $AgentsRoot -Directory -ErrorAction Stop |
                        ForEach-Object { Join-Path $_.FullName "_work" } |
                        Where-Object { Test-Path $_ }

    if ($agentWorkFolders.Count -eq 0) {
        Write-Log "Aucun dossier '_work' trouvé dans $AgentsRoot" "Yellow"
        Write-Log "Nettoyage terminé - rien à faire." "Green"
        exit 0
    }

    Write-Log "Dossiers '_work' trouvés: $($agentWorkFolders.Count)" "Cyan"

    $totalDeleted = 0
    $totalErrors = 0

    foreach ($workFolder in $agentWorkFolders) {
        Write-Log "`nNettoyage des dossiers de build dans : $workFolder" "Yellow"
        
        # Lister uniquement les sous-dossiers numériques
        $folders = Get-ChildItem -Path $workFolder -Directory -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match '^[0-9]+$' }
        
        if ($folders.Count -eq 0) {
            Write-Log "Aucun dossier numérique trouvé dans $workFolder" "Gray"
            continue
        }

        Write-Log "Dossiers à supprimer: $($folders.Count)" "Cyan"

        foreach ($folder in $folders) {
            try {
                # Vérifier si le dossier existe encore
                if (-not (Test-Path $folder.FullName)) {
                    Write-Log "Dossier déjà supprimé: $($folder.FullName)" "Gray"
                    continue
                }

                # Utiliser la fonction robuste
                if (Remove-FolderRobust -Path $folder.FullName) {
                    $totalDeleted++
                } else {
                    $totalErrors++
                }
                
            } catch {
                Write-Log "  Erreur inattendue : $($folder.FullName)" "Red"
                Write-Log "   Détails: $($_.Exception.Message)" "Red"
                $totalErrors++
            }
        }
    }

    # Résumé final
    Write-Log "`n=== Résumé du nettoyage ===" "Magenta"
    Write-Log "Dossiers supprimés avec succès: $totalDeleted" "Green"
    Write-Log "Erreurs rencontrées: $totalErrors" $(if ($totalErrors -gt 0) { "Red" } else { "Green" })
    Write-Log "Nettoyage terminé pour tous les agents." "Green"

} catch {
    Write-Log "Erreur critique: $($_.Exception.Message)" "Red"
    exit 1
}

# Code de sortie
if ($totalErrors -gt 0) {
    Write-Log "Script terminé avec des erreurs." "Yellow"
    exit 1
} else {
    Write-Log "Script terminé avec succès." "Green"
    exit 0
}
