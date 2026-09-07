import os
import json
import locale
import sys

# --- [ LOCALIZATION ENGINE CLASS ] ---

LOCALES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "locales")
if not os.path.exists(LOCALES_DIR):
    LOCALES_DIR = "/usr/share/slacky-update/locales"

CONFIG_FILE = os.path.expanduser("~/.config/slacky-update/config.json")

class I18nEngine:
    def __init__(self, override_lang=None):
        self.translations = {}
        self.fallback_translations = {}
        self.current_lang = "en"
        self.manual_override = None
        self.load_config()
        self.load_language(override_lang)

    def load_config(self):
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                    cfg = json.load(f)
                    self.manual_override = cfg.get("language_override")
            except Exception:
                self.manual_override = None

    def save_language_override(self, lang_code):
        os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
        cfg = {}
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                    cfg = json.load(f)
            except Exception:
                cfg = {}
        
        if lang_code is None or lang_code == "system":
            cfg.pop("language_override", None)
            self.manual_override = None
        else:
            cfg["language_override"] = lang_code
            self.manual_override = lang_code

        try:
            with open(CONFIG_FILE, "w", encoding="utf-8") as f:
                json.dump(cfg, f, indent=2)
        except Exception:
            pass

        self.load_language()

    def _detect_language(self):
        if self.manual_override and self.manual_override != "system":
            return self.manual_override

        for env_var in ("LC_ALL", "LC_MESSAGES", "LANG", "LANGUAGE"):
            val = os.environ.get(env_var)
            if val:
                raw_tag = val.split(".")[0].split(":")[0].replace("_", "-").lower()
                if os.path.exists(os.path.join(LOCALES_DIR, f"{raw_tag}.json")):
                    return raw_tag
                code = raw_tag.split("-")[0]
                if code and code not in ("c", "posix"):
                    return code

        try:
            sys_lang = locale.getdefaultlocale()[0]
            if sys_lang:
                raw_tag = sys_lang.replace("_", "-").lower()
                if os.path.exists(os.path.join(LOCALES_DIR, f"{raw_tag}.json")):
                    return raw_tag
                code = raw_tag.split("-")[0]
                if code and code not in ("c", "posix"):
                    return code
        except Exception:
            pass

        return "en"

    def load_language(self, lang_code=None):
        if not lang_code:
            lang_code = self._detect_language()

        self.current_lang = lang_code

        en_path = os.path.join(LOCALES_DIR, "en.json")
        if os.path.exists(en_path):
            try:
                with open(en_path, "r", encoding="utf-8") as f:
                    self.fallback_translations = json.load(f)
            except Exception:
                self.fallback_translations = {}

        target_path = os.path.join(LOCALES_DIR, f"{lang_code}.json")
        if os.path.exists(target_path):
            try:
                with open(target_path, "r", encoding="utf-8") as f:
                    self.translations = json.load(f)
            except Exception:
                self.translations = self.fallback_translations
        else:
            self.translations = self.fallback_translations

    def get_available_languages(self):
        langs = {}
        if os.path.exists(LOCALES_DIR):
            for f in sorted(os.listdir(LOCALES_DIR)):
                if f.endswith(".json"):
                    code = f[:-5]
                    try:
                        with open(os.path.join(LOCALES_DIR, f), "r", encoding="utf-8") as jf:
                            d = json.load(jf)
                            langs[code] = d.get("LANG_NAME", code)
                    except Exception:
                        langs[code] = code
        return langs

    def get(self, key, **kwargs):
        text = self.translations.get(key) or self.fallback_translations.get(key) or key
        if kwargs:
            try:
                return text.format(**kwargs)
            except Exception:
                return text
        return text

i18n = I18nEngine()
_ = i18n.get

if __name__ == "__main__":
    if len(sys.argv) > 1:
        key = sys.argv[1]
        kwargs = {}
        for arg in sys.argv[2:]:
            if "=" in arg:
                k, v = arg.split("=", 1)
                kwargs[k] = v
        print(_(key, **kwargs))
