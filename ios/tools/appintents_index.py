#!/usr/bin/env python3
"""Schreibt den App-Intents-Index (Metadata.appintents) für App und Widget-Erweiterung (E83).

iOS liest App Intents nur aus diesem Index. Xcode erzeugt ihn mit dem macOS-Werkzeug appintentsmetadataprocessor,
xtool nicht. Eingabe sind die .swiftconstvalues, die Swift Build unter Linux selbst schreibt. Ausgabeformat wie
Xcode 26.6 (17F113), abgeglichen mit echten Xcode-Indizes (cyberneel/xtool-on-linux reference/golden, qyang-nj/llios,
Widget-Konfiguration: mengtnt.com). Unterstützt nur, was Essenapp braucht: Intents mit Text-Parametern,
LiveActivityIntent und WidgetConfigurationIntent – alles andere bricht mit Fehler ab statt einen falschen Index zu schreiben.

In WSL nach ./build.sh build:  python3 tools/appintents_index.py           (schreibt ios/AppIntents/…)
                               python3 tools/appintents_index.py --check   (Fehler, wenn der Index veraltet ist)
Danach erneut bauen, damit xtool den Index ins Bundle kopiert.
"""
import json
import sys
from pathlib import Path

IOS = Path(__file__).resolve().parent.parent
BUILD = Path.home() / "build/essenapp-ios/.build/out/Intermediates.noindex/Essenapp.build/Debug-iphoneos"
APP_ID = "de.jsenf.essenapp"
SHARED = "EssenappShareUI"
# Programm im Bundle → (Bundle-ID, Module darin). xtool: Erweiterung = <App-ID>.<Produkt>
BUNDLES = {
    "Essenapp": (APP_ID, [SHARED, "Essenapp"]),
    "EssenappWidget": (f"{APP_ID}.EssenappWidget", [SHARED, "EssenappWidget"]),
}
TOOLS = "17F113"
# Konformität → Systemprotokoll im Index (LiveActivityIntent: MicYou-iOS auf dem Gerät, Widget: Xcode-Index)
SYSTEM = {
    "AppIntents.LiveActivityIntent": "com.apple.link.systemProtocol.SessionStarting",
    "AppIntents.WidgetConfigurationIntent": "com.apple.link.systemProtocol.WidgetConfiguration",
}
PLAIN = {"AppIntents.AppIntent", "AppIntents.SystemIntent", "AppIntents.PersistentlyIdentifiable", "AppIntents._SupportsAppDependencies"}
STRING = {"primitive": {"wrapper": {"typeIdentifier": 0}}}
# So schreibt Xcode 17F113 einen String-Parameter (golden: AskGoldenIntent.prompt)
STRING_INPUTS = [
    {"kindValue": 0, "valueType": STRING},
    {"kindValue": 0, "valueType": {"array": {"wrapper": {"capabilities": 3, "memberValueType": {"primitive": {"wrapper": {"typeIdentifier": 2}}}}}}},
    {"kindValue": 0, "valueType": {"primitive": {"wrapper": {"typeIdentifier": 2}}}},
]


class Unsupported(Exception):
    pass


def key(text):
    return {"alternatives": [], "key": text}


def text(value, what):
    """RawLiteral oder Init-Aufruf mit Literal als erstem Argument (IntentDescription("…"))."""
    if value is None:
        return None
    if value.get("valueKind") == "RawLiteral":
        return value["value"]
    if value.get("valueKind") == "InitCall":
        args = value["value"]["arguments"]
        if args and args[0].get("valueKind") == "RawLiteral":
            return args[0]["value"]
    raise Unsupported(f"{what}: nur Text-Literale möglich ({value.get('valueKind')})")


def prop(entry, label):
    return next((p for p in entry.get("properties", []) if p["label"] == label), None)


def parameter(p, intent):
    kind = p["type"]
    if kind not in ("AppIntents.IntentParameter<Swift.String>", "AppIntents.IntentParameter<Swift.Optional<Swift.String>>"):
        raise Unsupported(f"{intent}.{p['label']}: nur String-Parameter ({kind})")
    args = {a["label"]: a for a in p["value"]["arguments"]}
    if args.get("default", {}).get("valueKind", "NilLiteral") != "NilLiteral":
        raise Unsupported(f"{intent}.{p['label']}: Standardwert nicht unterstützt")
    out = {
        "capabilities": 0, "dynamicOptionsSupport": 0, "inputConnectionBehavior": 0, "isInput": False,
        "isOptional": "Optional" in kind, "name": p["label"][1:], "resolvableInputTypes": STRING_INPUTS,
        "title": key(text(args["title"], f"{intent}.{p['label']}.title")), "typeSpecificMetadata": [], "valueType": STRING,
    }
    if "description" in args and args["description"].get("valueKind") != "NilLiteral":
        out["parameterDescription"] = key(text(args["description"], f"{intent}.{p['label']}.description"))
    return out


def action(entry, bundle_ids):
    name = entry["typeName"]
    protocols = []
    for c in entry["conformances"]:
        if c in SYSTEM:
            protocols.append(SYSTEM[c])
        elif c.startswith("AppIntents.") and c not in PLAIN:
            raise Unsupported(f"{name}: {c} nicht unterstützt")
    for alias in entry.get("associatedTypeAliases", []):
        # WidgetConfigurationIntent ohne perform(): Never
        if alias["typeAliasName"] == "PerformResult" and alias.get("opaqueTypeProtocolRequirements") != ["AppIntents.IntentResult"]                 and alias["substitutedTypeName"] != "Swift.Never":
            raise Unsupported(f"{name}: perform() darf nur `some IntentResult` liefern")
    params = [parameter(p, name) for p in entry.get("properties", []) if p["label"].startswith("_") and p["type"].startswith("AppIntents.IntentParameter<")]
    title = text(prop(entry, "title"), f"{name}.title")
    if title is None:
        raise Unsupported(f"{name}: kein Titel")
    opens = text(prop(entry, "openAppWhenRun"), f"{name}.openAppWhenRun") == "true"
    discoverable = text(prop(entry, "isDiscoverable"), f"{name}.isDiscoverable") != "false"
    by_bundle = {b: entry["mangledTypeName"] for b in bundle_ids}
    meta = [x for p in sorted(protocols) for x in (p, {"empty": {}})]
    out = {
        "assistantDefinedSchemaTraits": [], "assistantDefinedSchemas": [], "authenticationPolicy": 0,
        "availabilityAnnotations": {"LNPlatformNameWildcard": {"introducedVersion": "*"}},
        "effectiveBundleIdentifiers": [], "fullyQualifiedTypeName": name, "identifier": name.split(".")[-1],
        "isAuthPolExplicit": False, "isDiscoverable": discoverable, "mangledTypeName": entry["mangledTypeName"],
        "mangledTypeNameByBundleIdentifier": by_bundle, "mangledTypeNameByBundleIdentifierV2": by_bundle,
        "mangledTypeNameV2": entry["mangledTypeName"], "openAppWhenRun": opens, "outputFlags": 0, "parameters": params,
        "presentationStyle": 0, "requiredCapabilities": [], "supportedModes": 2 if opens else 1,
        "systemProtocolMetadata": meta, "systemProtocolMetadataV2": meta, "systemProtocols": sorted(protocols),
        "title": key(title), "typeSpecificMetadata": [],
        "visibilityMetadata": {"assistantOnly": False, "isDiscoverable": discoverable},
    }
    description = text(prop(entry, "description"), f"{name}.description")
    if description is not None:
        out["descriptionMetadata"] = {"descriptionText": key(description), "searchKeywords": []}
    return out


def index(modules, all_ids):
    actions = {}
    for module in modules:
        files = sorted((BUILD / f"{module}-t.build/Objects-normal/arm64").glob("*.swiftconstvalues"))
        if not files:
            sys.exit(f"Keine .swiftconstvalues für {module} unter {BUILD} – erst ./build.sh build")
        for f in files:
            for entry in json.loads(f.read_text(encoding="utf-8")):
                conformances = entry.get("conformances", [])
                if "AppIntents.AppIntent" in conformances:
                    a = action(entry, all_ids if module == SHARED else [])
                    actions[a["identifier"]] = a
                elif any(c.startswith("AppIntents.") for c in conformances):
                    raise Unsupported(f"{entry['typeName']}: {conformances} nicht unterstützt")
    return {
        "actions": actions, "assistantEntities": [], "assistantIntentNegativePhrases": [], "assistantIntents": [],
        "autoShortcuts": [], "entities": {}, "enums": [], "generator": {"name": "xcode-tools", "version": TOOLS},
        "negativePhrases": [], "queries": {}, "shortcutTileColor": 14, "version": 1,
    }


def main():
    all_ids = sorted(b for b, _ in BUNDLES.values())
    files = {}
    for program, (_, modules) in BUNDLES.items():
        try:
            data = index(modules, all_ids)
        except Unsupported as e:
            sys.exit(f"App-Intents-Index für {program}: {e}")
        out = IOS / "AppIntents" / program / "Metadata.appintents"
        files[out / "extract.actionsdata"] = json.dumps(data, indent=4, sort_keys=True, ensure_ascii=False) + "\n"
        files[out / "version.json"] = '{\n  "version" : "3.0",\n  "toolsVersion" : "%s"\n}\n' % TOOLS
        print(f"{program}: {', '.join(sorted(data['actions'])) or '–'}")
    if "--check" in sys.argv:
        stale = [str(p.relative_to(IOS)) for p, t in files.items() if not p.exists() or p.read_text(encoding="utf-8") != t]
        if stale:
            sys.exit("App-Intents-Index veraltet, python3 tools/appintents_index.py ausführen: " + ", ".join(stale))
        return
    for p, t in files.items():
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(t, encoding="utf-8")


if __name__ == "__main__":
    main()
