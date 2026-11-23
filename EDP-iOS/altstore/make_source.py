"""Écrit apps.json : la « source » AltStore qui annonce les dernières versions d'EDP et de Tri.

Dans AltStore : Sources › + › https://github.com/<toi>/<dépôt>/releases/latest/download/apps.json
(fonctionne si le dépôt GitHub est public ; sinon, installe les .ipa à la main avec « + »).
"""
import json
import os
import plistlib
from datetime import datetime, timezone

repo = os.environ["REPO"]            # ex. robin/edp-ios
tag = os.environ["TAG"]              # ex. v1.0.12
version = os.environ["VERSION"]      # ex. 1.0.12
today = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
raw = f"https://raw.githubusercontent.com/{repo}/main"

APPS = [
    {
        "name": "EDP", "bundle": "fr.bizzari.edp", "plist": "Support/Info.plist", "tint": "#111113",
        "icon": "EDP/Assets.xcassets/AppIcon.appiconset/icon-1024.png",
        "subtitle": "Emploi du temps, devoirs et notes",
        "description": "EDP réunit ton emploi du temps, tes devoirs, tes notes et ta messagerie Pronote, le cahier de textes de l'ENT, "
                       "tes événements, ton bus du matin, tes habits du jour et l’actu. L'appli ajoute la connexion ÉduConnect "
                       "et les rappels.",
        "category": "education",
    },
    {
        "name": "Tri", "bundle": "fr.bizzari.tri", "plist": "SupportTri/Info.plist", "tint": "#0A84FF",
        "icon": "Tri/Assets.xcassets/AppIcon.appiconset/icon-1024.png",
        "subtitle": "Fais le ménage dans ta galerie",
        "description": "Tri analyse toute ta photothèque sur ton iPhone (doublons, photos floues, sombres, captures d'écran), "
                       "te fait trier au swipe mois par mois, puis supprime pour de vrai ce que tu as jeté (30 jours dans « Supprimés récemment »). "
                       "Aucune photo n'est envoyée sur Internet.",
        "category": "photo-video",
    },
]


def app_entry(a):
    ipa = f"{a['name']}.ipa"
    size = os.path.getsize(ipa)
    with open(a["plist"], "rb") as f:
        info = plistlib.load(f)
    privacy = {k: v for k, v in info.items() if k.startswith("NS") and k.endswith("UsageDescription")}
    download = f"https://github.com/{repo}/releases/download/{tag}/{ipa}"
    icon = f"{raw}/{a['icon']}"
    return {
        "name": a["name"],
        "bundleIdentifier": a["bundle"],
        "developerName": "Robin",
        "subtitle": a["subtitle"],
        "localizedDescription": a["description"],
        "iconURL": icon,
        "tintColor": a["tint"],
        "category": a["category"],
        "screenshots": [],
        "versions": [{
            "version": version, "date": today, "localizedDescription": f"Version {version}",
            "downloadURL": download, "size": size, "minOSVersion": "16.0",
        }],
        "appPermissions": {"entitlements": [], "privacy": privacy},
        # anciens champs, pour les versions d'AltStore plus anciennes
        "version": version, "versionDate": today, "versionDescription": f"Version {version}",
        "downloadURL": download, "size": size,
    }


source = {
    "name": "Applis de Robin",
    "identifier": f"io.github.{repo.replace('/', '.').lower()}",
    "sourceURL": f"https://github.com/{repo}/releases/latest/download/apps.json",
    "subtitle": "EDP et Tri",
    "tintColor": "#111113",
    "iconURL": f"{raw}/{APPS[0]['icon']}",
    "apps": [app_entry(a) for a in APPS if os.path.exists(f"{a['name']}.ipa")],
    "news": [],
}

with open("apps.json", "w", encoding="utf-8") as f:
    json.dump(source, f, ensure_ascii=False, indent=2)
print("apps.json écrit :", ", ".join(f"{x['name']} {version}" for x in source["apps"]))
