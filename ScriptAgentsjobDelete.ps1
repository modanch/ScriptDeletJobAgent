<#
.SYNOPSIS
Skript zum Löschen der im Ordner _work gespeicherten Agent-Jobs

.DESCRIPTION
Dieses Skript wird nach dem Neustart des Servers ausgeführt, jedoch nur zwischen 23 Uhr und 1 Uhr morgens.
Es löscht die  Aufgaben, die von den Agenten während des Tages erstellt wurden,
da diese leicht Speicherplatz auf der Festplatte belegen können.

.NOTES
Auteur : A. Eggenschwiler
Date : 14.08.2025

.LINK
https://modan.ch
#>

$AgentsRoot = "C:\AzureDevOpsAgents"  # Chemin vers vos agents
$LogFolder = "C:\AgentsDeleteLog"
$LogFile = "$LogFolder\cleanup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"  # Fichier de log

# === FONCTIONS ===
function Write-Log {
    param(
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $Message"
    Write-Host $logMessage

    # Créer le dossier du fichier de log si nécessaire
    $logDir = Split-Path $LogFile -Parent
    if ($logDir -and -not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    # Écrire dans le fichier de log
    $logMessage | Out-File -FilePath $LogFile -Append -Encoding utf8
}

# === CONDITION HORAIRE (23h–1h) ===
$now   = Get-Date
$start = [datetime]::Today.AddHours(23)    # 23:00 aujourd'hui
$end   = [datetime]::Today.AddDays(1).AddHours(1)  # 01:00 demain

if ($now -lt $start -or $now -ge $end) {
    Write-Log "Script ignoré : hors de la fenêtre horaire (23h00-01h00)."
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

    Write-Log "Suppression du dossier : $Path"

    # Supprimer les attributs en lecture seule récursivement
    try {
        Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReadOnly } |
            ForEach-Object {
                try {
                    $_.Attributes = $_.Attributes -band -bnot [System.IO.FileAttributes]::ReadOnly
                } catch {
                    # Ignorer les erreurs liées aux attributs
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
            Write-Log "Suppression réussie (tentative $i)."
            return $true
        } catch {
            Write-Log "Tentative $i échouée : $($_.Exception.Message)"
            if ($i -lt $maxAttempts) {
                Start-Sleep -Seconds 2
            }
        }
    }

    # Dernière tentative avec rmdir (plus fiable pour les gros volumes)
    try {
        Write-Log "Tentative finale avec rmdir..."
        cmd.exe /c "rmdir /s /q `"$Path`"" 2>$null

        if (-not (Test-Path $Path)) {
            Write-Log "Suppression réussie avec rmdir."
            return $true
        } else {
            Write-Log "Échec final : le dossier est toujours présent."
        }
    } catch {
        Write-Log "Échec final avec rmdir : $($_.Exception.Message)"
    }

    return $false
}

# === SCRIPT PRINCIPAL ===
# Vérification du chemin racine
if (-not (Test-Path $AgentsRoot)) {
    Write-Log "ERREUR : le chemin AgentsRoot '$AgentsRoot' n'existe pas."
    Write-Log "Veuillez modifier la variable `$AgentsRoot dans ce script."
    exit 1
}

# Initialisation
Write-Log "=== Début du nettoyage des dossiers de build ==="
Write-Log "Racine des agents : $AgentsRoot"
Write-Log "Fichier de log : $LogFile"

try {
    # Trouver tous les sous-dossiers contenant _work
    $agentWorkFolders = Get-ChildItem -Path $AgentsRoot -Directory -ErrorAction Stop |
                        ForEach-Object { Join-Path $_.FullName "_work" } |
                        Where-Object { Test-Path $_ }

    if ($agentWorkFolders.Count -eq 0) {
        Write-Log "Aucun dossier '_work' trouvé dans $AgentsRoot."
        Write-Log "Nettoyage terminé - aucune action nécessaire."
        exit 0
    }

    Write-Log "Nombre de dossiers '_work' trouvés : $($agentWorkFolders.Count)"

    $totalDeleted = 0
    $totalErrors = 0

    foreach ($workFolder in $agentWorkFolders) {
        Write-Log "`nNettoyage des dossiers de build dans : $workFolder"

        # Lister uniquement les sous-dossiers numériques
        $folders = Get-ChildItem -Path $workFolder -Directory -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match '^[0-9]+$' }

        if ($folders.Count -eq 0) {
            Write-Log "Aucun dossier numérique trouvé dans $workFolder."
            continue
        }

        Write-Log "Dossiers à supprimer : $($folders.Count)"

        foreach ($folder in $folders) {
            try {
                if (-not (Test-Path $folder.FullName)) {
                    Write-Log "Dossier déjà supprimé : $($folder.FullName)"
                    continue
                }

                if (Remove-FolderRobust -Path $folder.FullName) {
                    $totalDeleted++
                } else {
                    $totalErrors++
                }

            } catch {
                Write-Log "Erreur inattendue : $($folder.FullName)"
                Write-Log "Détails : $($_.Exception.Message)"
                $totalErrors++
            }
        }
    }

    # Résumé final
    Write-Log "`n=== Résumé du nettoyage ==="
    Write-Log "Dossiers supprimés avec succès : $totalDeleted"
    Write-Log "Erreurs rencontrées : $totalErrors"
    Write-Log "Nettoyage terminé pour tous les agents."

} catch {
    Write-Log "Erreur critique : $($_.Exception.Message)"
    exit 1
}

# Code de sortie
if ($totalErrors -gt 0) {
    Write-Log "Script terminé avec des erreurs."
    exit 1
} else {
    Write-Log "Script terminé avec succès."
    exit 0
}
