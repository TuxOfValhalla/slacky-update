#!/usr/bin/env bash
# ==============================================================================
# slacky-update: mod_docs.sh - Master Field Guide & Multi-Format Export Engine
# ==============================================================================
# set -euo pipefail

get_master_field_guide_md_path() {
    local candidates=(
        "${SCRIPT_DIR:-}/../SURVIVAL_GUIDE.md"
        "${APP_DIR:-}/../SURVIVAL_GUIDE.md"
        "${APP_DIR:-}/SURVIVAL_GUIDE.md"
        "${SCRIPT_DIR:-}/../docs/SLACKY_UPDATE_FIELD_GUIDE.md"
        "${APP_DIR:-}/../docs/SLACKY_UPDATE_FIELD_GUIDE.md"
        "${APP_DIR:-}/docs/SLACKY_UPDATE_FIELD_GUIDE.md"
        "/usr/share/slacky-update/docs/SURVIVAL_GUIDE.md"
        "/usr/share/slacky-update/docs/SLACKY_UPDATE_FIELD_GUIDE.md"
        "/usr/local/share/slacky-update/docs/SURVIVAL_GUIDE.md"
        "/usr/local/lib/slacky-update/docs/SURVIVAL_GUIDE.md"
        "/usr/local/lib/slacky-update/docs/SLACKY_UPDATE_FIELD_GUIDE.md"
        "${SCRIPT_DIR:-}/../docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md"
        "${APP_DIR:-}/../docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md"
        "/usr/share/slacky-update/docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md"
    )
    for c in "${candidates[@]}"; do
        if [ -f "${c}" ]; then
            echo "${c}"
            return 0
        fi
    done
    echo ""
}

get_technical_companion_guide_md_path() {
    local candidates=(
        "${SCRIPT_DIR:-}/../TECHNICAL_COMPANION_GUIDE.md"
        "${APP_DIR:-}/../TECHNICAL_COMPANION_GUIDE.md"
        "${APP_DIR:-}/TECHNICAL_COMPANION_GUIDE.md"
        "${SCRIPT_DIR:-}/../docs/TECHNICAL_COMPANION_GUIDE.md"
        "${APP_DIR:-}/../docs/TECHNICAL_COMPANION_GUIDE.md"
        "${APP_DIR:-}/docs/TECHNICAL_COMPANION_GUIDE.md"
        "/usr/share/slacky-update/docs/TECHNICAL_COMPANION_GUIDE.md"
        "/usr/local/share/slacky-update/docs/TECHNICAL_COMPANION_GUIDE.md"
        "/usr/local/lib/slacky-update/docs/TECHNICAL_COMPANION_GUIDE.md"
    )
    for c in "${candidates[@]}"; do
        if [ -f "${c}" ]; then
            echo "${c}"
            return 0
        fi
    done
    echo ""
}

get_limine_field_guide_md_path() {
    local candidates=(
        "${SCRIPT_DIR:-}/../docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md"
        "${APP_DIR:-}/../docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md"
        "${APP_DIR:-}/docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md"
        "/usr/share/slacky-update/docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md"
        "/usr/local/share/slacky-update/docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md"
        "/usr/local/lib/slacky-update/docs/LIMINE_SECUREBOOT_FIELD_GUIDE.md"
    )
    for c in "${candidates[@]}"; do
        if [ -f "${c}" ]; then
            echo "${c}"
            return 0
        fi
    done
    echo ""
}

get_troubleshooting_guide_md_path() {
    local candidates=(
        "${SCRIPT_DIR:-}/../docs/TROUBLESHOOTING_GUIDE.md"
        "${APP_DIR:-}/../docs/TROUBLESHOOTING_GUIDE.md"
        "${APP_DIR:-}/docs/TROUBLESHOOTING_GUIDE.md"
        "/usr/share/slacky-update/docs/TROUBLESHOOTING_GUIDE.md"
        "/usr/local/share/slacky-update/docs/TROUBLESHOOTING_GUIDE.md"
        "/usr/local/lib/slacky-update/docs/TROUBLESHOOTING_GUIDE.md"
    )
    for c in "${candidates[@]}"; do
        if [ -f "${c}" ]; then
            echo "${c}"
            return 0
        fi
    done
    echo ""
}

# --- [ PDF GENERATOR (Enhanced Groff -ms / TBL / PS2PDF) ] ---
generate_field_guide_pdf() {
    local target_pdf="${1:-/tmp/Slacky_Update_Field_Guide.pdf}"
    local md_path="${2:-}"
    if [ -z "${md_path}" ]; then
        md_path=$(get_master_field_guide_md_path)
    fi

    if [ -z "${md_path}" ] || [ ! -f "${md_path}" ]; then
        log_error "Field Guide markdown file not found."
        return 1
    fi

    if ! command -v groff >/dev/null 2>&1 || ! command -v ps2pdf >/dev/null 2>&1; then
        log_error "PDF generation requires 'groff' and 'ps2pdf' (ghostscript). Please install standard Slackware packages (d/groff, ap/ghostscript)."
        return 1
    fi

    log_info "Compiling field guide into standalone PDF document..."
    python3 - << PYPDF
import os, re, subprocess

md_path = "${md_path}"
target_pdf = "${target_pdf}"

with open(md_path, "r", encoding="utf-8") as f:
    lines = f.readlines()

out = [
    ".nr PS 10p",
    ".nr VS 14p",
    ".nr HM 1.0i",
    ".nr FM 1.0i",
    ".nr PO 0.8i",
    ".nr LL 6.9i",
    ".fam H",
    ".ds LH \\\\fBSlacky-Update\\\\fR",
    ".ds CH \\\\fISystem Manual\\\\fR",
    ".ds RH \\\\fBSeptember 2026\\\\fR",
    ".ds CF - % -",
    ".LP",
]

def inline_format(text):
    text = text.replace("\\\\", "\\\\e")
    text = re.sub(r'\*\*(.*?)\*\*', r'\\\\fB\1\\\\fR', text)
    text = re.sub(r'(?<!\*)\*([^*]+)\*(?!\*)', r'\\\\fI\1\\\\fR', text)
    text = re.sub(r'\`([^\`]+)\`', r'\\\\f(CR\1\\\\fR', text)
    text = re.sub(r'\[(.*?)\]\(.*?\)', r'\\\\fB\1\\\\fR', text)
    return text

in_code = False
in_table = False
table_rows = []

for line in lines:
    raw = line.rstrip()

    if raw.startswith("\`\`\`"):
        if in_code:
            out.append(".fam H")
            out.append(".ps 10")
            out.append(".vs 14p")
            out.append(".RE")
            out.append(".LP")
            in_code = False
        else:
            out.append(".LP")
            out.append(".RS 2")
            out.append(".fam C")
            out.append(".ps 8.5")
            out.append(".vs 11p")
            out.append(".nf")
            in_code = True
        continue

    if in_code:
        out.append(raw.replace("\\\\", "\\\\e"))
        continue

    if raw.startswith("|") and raw.endswith("|"):
        if re.match(r'^\|[\s:-]+\|', raw):
            continue
        cells = [c.strip() for c in raw.strip('|').split('|')]
        table_rows.append(cells)
        in_table = True
        continue
    elif in_table:
        if table_rows:
            out.append(".LP")
            out.append(".TS")
            out.append("allbox tab(@);")
            out.append("cb cb")
            out.append("lw(2.5i) lw(4.0i).")
            out.append(" @ ".join([inline_format(c) for c in table_rows[0]]))
            out.append("_")
            for r in table_rows[1:]:
                if len(r) >= 2:
                    out.append(f"{inline_format(r[0])}@T{{\n{inline_format(r[1])}\nT}}")
                else:
                    out.append(" @ ".join([inline_format(c) for c in r]))
            out.append(".TE")
            out.append(".LP")
            table_rows = []
        in_table = False

    if raw.startswith("# "):
        out.append(".sp 1.2")
        out.append(".fam H")
        out.append(".ps 16")
        out.append(".vs 20p")
        out.append(f'.B "{inline_format(raw[2:])}"')
        out.append(".ps 10")
        out.append(".vs 14p")
        out.append(".LP")
    elif raw.startswith("## "):
        out.append(".sp 0.8")
        out.append(".fam H")
        out.append(".ps 13")
        out.append(".vs 16p")
        out.append(f'.B "{inline_format(raw[3:])}"')
        out.append(".ps 10")
        out.append(".vs 14p")
        out.append(".LP")
    elif raw.startswith("### "):
        out.append(".sp 0.5")
        out.append(".fam H")
        out.append(".ps 11")
        out.append(".vs 14p")
        out.append(f'.B "{inline_format(raw[4:])}"')
        out.append(".ps 10")
        out.append(".vs 14p")
        out.append(".LP")
    elif raw.startswith("#### "):
        out.append(".sp 0.3")
        out.append(".fam H")
        out.append(".ps 10.5")
        out.append(f'.I "{inline_format(raw[5:])}"')
        out.append(".ps 10")
        out.append(".LP")
    elif raw.startswith("* ") or raw.startswith("- "):
        out.append(".IP \\\\(bu 2")
        out.append(inline_format(raw[2:]))
    elif re.match(r'^\d+\.\s', raw):
        num, rest = raw.split(". ", 1)
        out.append(f".IP {num}. 3")
        out.append(inline_format(rest))
    elif raw == "---":
        out.append(".LP")
        out.append(".sp 0.5")
        out.append(".HL")
        out.append(".sp 0.5")
    elif raw.strip() == "":
        out.append(".LP")
    else:
        out.append(inline_format(raw))

groff_code = "\n".join(out)

os.makedirs(os.path.dirname(os.path.abspath(target_pdf)), exist_ok=True)
p1 = subprocess.Popen(["groff", "-Kutf8", "-t", "-ms", "-Tps"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
p2 = subprocess.Popen(["ps2pdf", "-", target_pdf], stdin=p1.stdout, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
p1.stdin.write(groff_code.encode("utf-8"))
p1.stdin.close()
p2.communicate()
PYPDF

    if [ -f "${target_pdf}" ] && [ -s "${target_pdf}" ]; then
        log_success "PDF generated successfully at: ${target_pdf}"
        return 0
    else
        log_error "Failed to generate PDF document."
        return 1
    fi
}

generate_limine_guide_pdf() {
    local target_pdf="${1:-/tmp/Limine_SecureBoot_Guide.pdf}"
    local md_path
    md_path=$(get_limine_field_guide_md_path)
    generate_field_guide_pdf "${target_pdf}" "${md_path}"
}

# --- [ HTML GENERATOR (Mobile & Offline Optimized) ] ---
# --- [ HTML GENERATOR (Mobile & Offline Optimized Multi-Guide Portal) ] ---
generate_field_guide_html() {
    local target_html="${1:-/tmp/Slacky_Update_Field_Guide.html}"
    local master_md="${2:-}"
    local limine_md="${3:-}"
    local tech_md="${4:-}"

    [ -z "${master_md}" ] && master_md=$(get_master_field_guide_md_path)
    [ -z "${limine_md}" ] && limine_md=$(get_limine_field_guide_md_path)
    [ -z "${tech_md}" ] && tech_md=$(get_technical_companion_guide_md_path)

    [ -f "${master_md}" ] || return 1

    python3 - << PYHTML
import html, os, re

master_md = "${master_md}"
limine_md = "${limine_md}"
tech_md = "${tech_md}"
target_html = "${target_html}"

def parse_markdown(md):
    if not md: return ""
    lines = md.split("\n")
    out = []
    in_code = False
    in_table = False
    table_rows = []

    for line in lines:
        if line.startswith("\`\`\`"):
            if in_code:
                out.append("</code></pre>")
                in_code = False
            else:
                out.append("<pre><code>")
                in_code = True
            continue
        if in_code:
            out.append(html.escape(line))
            continue

        if line.startswith("|") and line.endswith("|"):
            if re.match(r'^\|[\s:-]+\|', line):
                continue
            cells = [c.strip() for c in line.strip('|').split('|')]
            table_rows.append(cells)
            in_table = True
            continue
        elif in_table:
            if table_rows:
                out.append('<div class="table-wrap"><table>')
                out.append('<thead><tr>' + ''.join([f'<th>{html.escape(c)}</th>' for c in table_rows[0]]) + '</tr></thead>')
                out.append('<tbody>')
                for r in table_rows[1:]:
                    out.append('<tr>' + ''.join([f'<td>{html.escape(c)}</td>' for c in r]) + '</tr>')
                out.append('</tbody></table></div>')
                table_rows = []
            in_table = False

        if line.startswith("# "):
            out.append(f"<h1>{html.escape(line[2:])}</h1>")
        elif line.startswith("## "):
            out.append(f"<h2>{html.escape(line[3:])}</h2>")
        elif line.startswith("### "):
            out.append(f"<h3>{html.escape(line[4:])}</h3>")
        elif line.startswith("#### "):
            out.append(f"<h4>{html.escape(line[5:])}</h4>")
        elif line.startswith("* ") or line.startswith("- "):
            out.append(f"<li>{html.escape(line[2:])}</li>")
        elif re.match(r"^\d+\.\s", line):
            num, rest = line.split(". ", 1)
            out.append(f"<p><strong>{num}.</strong> {html.escape(rest)}</p>")
        elif line.strip() == "---":
            out.append("<hr/>")
        elif line.strip():
            l = html.escape(line)
            l = re.sub(r'\*\*(.*?)\*\*', r'<strong>\1</strong>', l)
            l = re.sub(r'\`(.*?)\`', r'<code>\1</code>', l)
            out.append(f"<p>{l}</p>")
    return "\n".join(out)

master_body = ""
if os.path.isfile(master_md):
    with open(master_md, "r", encoding="utf-8") as f:
        master_body = parse_markdown(f.read())

limine_body = ""
if os.path.isfile(limine_md):
    with open(limine_md, "r", encoding="utf-8") as f:
        limine_body = parse_markdown(f.read())

tech_body = ""
if os.path.isfile(tech_md):
    with open(tech_md, "r", encoding="utf-8") as f:
        tech_body = parse_markdown(f.read())

html_doc = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no"/>
  <title>Slacky-Update Master Field Guide & Offline Manual</title>
  <style>
    :root {{
      --bg: #0b0e14;
      --card-bg: #151921;
      --accent-blue: #58a6ff;
      --accent-green: #2ea043;
      --accent-yellow: #d29922;
      --accent-purple: #a371f7;
      --border: #30363d;
      --text: #e6edf3;
      --text-muted: #8b949e;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      line-height: 1.65;
      color: var(--text);
      background: var(--bg);
      margin: 0;
      padding: 12px;
      -webkit-text-size-adjust: 100%;
    }}
    .container {{
      max-width: 960px;
      margin: auto;
      background: var(--card-bg);
      padding: 18px;
      border-radius: 12px;
      border: 1px solid var(--border);
      box-shadow: 0 8px 24px rgba(0,0,0,0.6);
    }}
    .offline-banner {{
      background: linear-gradient(135deg, rgba(35, 134, 54, 0.25), rgba(31, 111, 235, 0.25));
      border: 1px solid var(--accent-green);
      border-radius: 10px;
      padding: 16px;
      margin-bottom: 20px;
    }}
    .offline-banner h2 {{
      margin: 0 0 8px 0;
      color: #3fb950;
      font-size: 1.25rem;
      display: flex;
      align-items: center;
      gap: 8px;
    }}
    .offline-banner p {{
      margin: 0 0 14px 0;
      font-size: 0.95rem;
      color: #f0f6fc;
    }}
    .download-grid {{
      display: grid;
      grid-template-columns: 1fr;
      gap: 12px;
      margin-bottom: 14px;
    }}
    @media (min-width: 600px) {{
      .download-grid {{ grid-template-columns: 1fr 1fr 1fr; }}
    }}
    .dl-btn {{
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 14px 12px;
      border-radius: 8px;
      font-weight: 700;
      font-size: 0.95rem;
      color: #ffffff !important;
      text-decoration: none !important;
      text-align: center;
      cursor: pointer;
      border: none;
      transition: opacity 0.2s, transform 0.1s;
      box-shadow: 0 3px 8px rgba(0,0,0,0.4);
    }}
    .dl-btn:active {{ transform: scale(0.97); }}
    .dl-btn span.sub {{ font-size: 0.75rem; font-weight: normal; opacity: 0.85; margin-top: 4px; }}
    .dl-btn-green {{ background: var(--accent-green); }}
    .dl-btn-blue {{ background: #1f6feb; }}
    .dl-btn-purple {{ background: var(--accent-purple); }}
    .action-links {{
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 10px;
      font-size: 0.85rem;
    }}
    .action-link {{
      background: #21262d;
      color: var(--accent-blue) !important;
      border: 1px solid var(--border);
      padding: 7px 12px;
      border-radius: 6px;
      text-decoration: none !important;
      cursor: pointer;
      display: inline-block;
    }}
    .tips-box {{
      background: rgba(210, 153, 34, 0.12);
      border-left: 4px solid var(--accent-yellow);
      padding: 10px 14px;
      margin-top: 12px;
      border-radius: 0 6px 6px 0;
      font-size: 0.85rem;
      color: #e3b341;
    }}
    .tips-box strong {{ color: #f0883e; }}
    .tabs-bar {{
      display: flex;
      gap: 6px;
      border-bottom: 2px solid var(--border);
      margin-bottom: 20px;
      overflow-x: auto;
      padding-bottom: 2px;
    }}
    .tab-btn {{
      background: #21262d;
      border: 1px solid var(--border);
      border-bottom: none;
      color: var(--text-muted);
      padding: 10px 16px;
      border-radius: 8px 8px 0 0;
      font-weight: 600;
      font-size: 0.92rem;
      cursor: pointer;
      white-space: nowrap;
    }}
    .tab-btn.active {{
      background: var(--card-bg);
      color: var(--accent-blue);
      border-color: var(--accent-blue) var(--border) var(--card-bg) var(--border);
      border-width: 2px 1px 0 1px;
    }}
    .tab-content {{ display: none; }}
    .tab-content.active {{ display: block; }}
    h1, h2, h3, h4 {{ color: var(--accent-blue); font-weight: 600; }}
    h1 {{ border-bottom: 2px solid var(--border); padding-bottom: 10px; font-size: 1.5rem; }}
    h2 {{ border-bottom: 1px solid #21262d; padding-bottom: 6px; margin-top: 28px; font-size: 1.25rem; }}
    h3 {{ font-size: 1.05rem; margin-top: 20px; }}
    a {{ color: #79c0ff; text-decoration: none; }}
    a:hover {{ text-decoration: underline; }}
    pre {{
      background: #06090e;
      padding: 14px;
      border-radius: 8px;
      border: 1px solid var(--border);
      overflow-x: auto;
      font-size: 13px;
    }}
    code {{
      font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
      color: #7ee787;
    }}
    li {{ margin-bottom: 6px; }}
    hr {{ border: 0; border-top: 1px solid var(--border); margin: 24px 0; }}
    .table-wrap {{ overflow-x: auto; margin: 16px 0; }}
    table {{ width: 100%; border-collapse: collapse; }}
    th, td {{ border: 1px solid var(--border); padding: 8px 12px; text-align: left; font-size: 13.5px; }}
    th {{ background: #21262d; color: #58a6ff; }}
    .status-pill {{
      display: inline-block;
      padding: 2px 8px;
      border-radius: 12px;
      font-size: 0.75rem;
      font-weight: bold;
      background: rgba(46, 160, 67, 0.2);
      color: #3fb950;
      border: 1px solid #2ea043;
    }}
  </style>
</head>
<body>
  <div class="container">
    <div class="offline-banner">
      <h2>📲 Slacky-Update Survival Center <span class="status-pill">Offline Ready</span></h2>
      <p>Last ned PDF-manualene til telefonen din nå, slik at du har full tilgang når PC-en startes på nytt inn i BIOS / UEFI!</p>
      
      <div class="download-grid">
        <a class="dl-btn dl-btn-green" href="/Slacky_Update_Field_Guide.pdf" download="Slacky_Update_Field_Guide.pdf">
          <span>📥 Survival Guide (PDF)</span>
          <span class="sub">Master System Manual</span>
        </a>
        <a class="dl-btn dl-btn-blue" href="/Limine_SecureBoot_Guide.pdf" download="Limine_SecureBoot_Guide.pdf">
          <span>📥 Limine & BIOS (PDF)</span>
          <span class="sub">Bootloader & Secure Boot Matrix</span>
        </a>
        <a class="dl-btn dl-btn-purple" href="/Technical_Companion_Guide.pdf" download="Technical_Companion_Guide.pdf">
          <span>📥 Technical Guide (PDF)</span>
          <span class="sub">Deep Architecture & Modules</span>
        </a>
      </div>

      <div class="action-links">
        <a class="action-link" href="/Slacky_Update_Field_Guide.pdf?inline=1" target="_blank">👁️ Åpne Survival PDF i fane</a>
        <a class="action-link" href="/Limine_SecureBoot_Guide.pdf?inline=1" target="_blank">👁️ Åpne Limine PDF i fane</a>
        <a class="action-link" href="/Technical_Companion_Guide.pdf?inline=1" target="_blank">👁️ Åpne Technical PDF i fane</a>
        <button class="action-link" onclick="window.print()">🖨️ Skriv ut / Lagre hele siden som PDF</button>
      </div>

      <div class="tips-box">
        <strong>📱 Nedlastingstips:</strong><br/>
        • <strong>Android / Chrome:</strong> Trykk på ønsket PDF for å lagre den direkte i *Nedlastinger*.<br/>
        • <strong>iOS / Safari:</strong> Trykk på PDF. Hvis den åpnes i Safari, trykk på Del-knappen (firkant med pil) ➔ <strong>"Lagre i Filer"</strong>.<br/>
        • <strong>Offline-modus:</strong> Alle 3 guidene er lastet inn på denne siden under fanene nedenfor. Den forblir åpen og lesbar selv om PC-en er i BIOS!
      </div>
    </div>

    <!-- TABS -->
    <div class="tabs-bar">
      <button class="tab-btn active" onclick="switchTab('tab-master', this)">📖 1. Survival Guide</button>
      <button class="tab-btn" onclick="switchTab('tab-limine', this)">🛡️ 2. Limine & BIOS Playbook</button>
      <button class="tab-btn" onclick="switchTab('tab-tech', this)">⚙️ 3. Technical Architecture</button>
    </div>

    <div id="tab-master" class="tab-content active">
      {master_body}
    </div>

    <div id="tab-limine" class="tab-content">
      {limine_body}
    </div>

    <div id="tab-tech" class="tab-content">
      {tech_body}
    </div>
  </div>

  <script>
    function switchTab(tabId, btn) {{
      document.querySelectorAll('.tab-content').forEach(el => el.classList.remove('active'));
      document.querySelectorAll('.tab-btn').forEach(el => el.classList.remove('active'));
      const target = document.getElementById(tabId);
      if (target) target.classList.add('active');
      if (btn) btn.classList.add('active');
      window.scrollTo({{ top: 0, behavior: 'smooth' }});
    }}

    // Cache offline content in localStorage and ServiceWorker if supported
    try {{
      localStorage.setItem('slacky_guide_offline_html', document.documentElement.outerHTML);
    }} catch(e) {{}}
  </script>
</body>
</html>"""

os.makedirs(os.path.dirname(os.path.abspath(target_html)), exist_ok=True)
with open(target_html, "w", encoding="utf-8") as f:
    f.write(html_doc)
PYHTML
    return 0
}

# --- [ TERMINAL PAGER VIEW ] ---
view_field_guide_terminal() {
    local md_path="${1:-}"
    if [ -z "${md_path}" ]; then
        md_path=$(get_master_field_guide_md_path)
    fi

    if [ -z "${md_path}" ] || [ ! -f "${md_path}" ]; then
        log_error "Field Guide document not found."
        return 1
    fi

    if command -v glow >/dev/null 2>&1; then
        glow -p "${md_path}"
    elif command -v bat >/dev/null 2>&1; then
        bat --paging=always "${md_path}"
    else
        less -R "${md_path}" || cat "${md_path}"
    fi
}

# --- [ EXPORT TO PDF ] ---
export_field_guide_pdf() {
    local current_user="${SUDO_USER:-${USER:-tux}}"
    local user_home
    user_home=$(eval echo "~${current_user}")

    local dest_dir="${user_home}/Documents"
    if [ ! -d "${dest_dir}" ] || [ ! -w "${dest_dir}" ]; then
        dest_dir="${user_home}/Desktop"
        if [ ! -d "${dest_dir}" ] || [ ! -w "${dest_dir}" ]; then
            dest_dir="${user_home}"
            [ -w "${dest_dir}" ] || dest_dir="/tmp"
        fi
    fi

    local target_pdf="${dest_dir}/Slacky_Update_Field_Guide.pdf"
    local tech_pdf="${dest_dir}/Technical_Companion_Guide.pdf"
    local limine_pdf="${dest_dir}/Limine_SecureBoot_Guide.pdf"
    local trouble_pdf="${dest_dir}/Disaster_Recovery_Guide.pdf"

    local master_md
    master_md=$(get_master_field_guide_md_path)
    local tech_md
    tech_md=$(get_technical_companion_guide_md_path)
    local limine_md
    limine_md=$(get_limine_field_guide_md_path)
    local trouble_md
    trouble_md=$(get_troubleshooting_guide_md_path)

    if generate_field_guide_pdf "${target_pdf}" "${master_md}"; then
        chown "${current_user}:" "${target_pdf}" 2>/dev/null || true

        if [ -n "${tech_md}" ] && [ -f "${tech_md}" ]; then
            generate_field_guide_pdf "${tech_pdf}" "${tech_md}" >/dev/null 2>&1 || true
            chown "${current_user}:" "${tech_pdf}" 2>/dev/null || true
        fi

        if [ -n "${limine_md}" ] && [ -f "${limine_md}" ]; then
            generate_field_guide_pdf "${limine_pdf}" "${limine_md}" >/dev/null 2>&1 || true
            chown "${current_user}:" "${limine_pdf}" 2>/dev/null || true
        fi

        if [ -n "${trouble_md}" ] && [ -f "${trouble_md}" ]; then
            generate_field_guide_pdf "${trouble_pdf}" "${trouble_md}" >/dev/null 2>&1 || true
            chown "${current_user}:" "${trouble_pdf}" 2>/dev/null || true
        fi

        echo ""
        log_success "System documentation PDFs exported successfully!"
        echo -e "  • ${BOLD}Master Survival Guide:${RESET}      ${CYAN}${target_pdf}${RESET}"
        if [ -f "${tech_pdf}" ]; then
            echo -e "  • ${BOLD}Technical Architecture Guide:${RESET} ${CYAN}${tech_pdf}${RESET}"
        fi
        if [ -f "${limine_pdf}" ]; then
            echo -e "  • ${BOLD}Limine & BIOS Playbook:${RESET}      ${CYAN}${limine_pdf}${RESET}"
        fi
        if [ -f "${trouble_pdf}" ]; then
            echo -e "  • ${BOLD}Disaster Recovery Guide:${RESET}     ${CYAN}${trouble_pdf}${RESET}"
        fi
        echo ""
    fi
}

# --- [ SEND VIA EMAIL (xdg-email) ] ---
send_field_guide_email() {
    local tmp_pdf="/tmp/Slacky_Update_Field_Guide.pdf"
    local master_md
    master_md=$(get_master_field_guide_md_path)
    generate_field_guide_pdf "${tmp_pdf}" "${master_md}" || return 1

    echo ""
    log_info "Preparing email with Master Field Guide PDF attached..."

    if command -v xdg-email >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
        xdg-email --attach "${tmp_pdf}" --subject "Slacky-Update Master Field Guide" --body "Attached is the complete system manual and field guide for Slacky-Update." "" 2>/dev/null || true
        log_success "Opened default desktop email client with PDF attached!"
    else
        read -r -p "Enter recipient email address: " recipient_email
        if [ -n "${recipient_email}" ]; then
            if command -v mailx >/dev/null 2>&1; then
                echo "Attached is the Slacky-Update Master Field Guide." | mailx -s "Slacky-Update Master Field Guide" -a "${tmp_pdf}" "${recipient_email}"
                log_success "Email sent to ${recipient_email}."
            elif command -v sendmail >/dev/null 2>&1; then
                echo "Subject: Slacky-Update Master Field Guide" | sendmail "${recipient_email}"
                log_success "Dispatched via sendmail."
            else
                log_warn "No configured mail transport agent found. PDF saved to ${tmp_pdf}."
            fi
        fi
    fi
}

# --- [ TRANSFER TO PHONE VIA WI-FI QR CODE ] ---
transfer_field_guide_qr() {
    local serve_dir="/tmp/slacky_guide_transfer"
    rm -rf "${serve_dir}" 2>/dev/null || true
    mkdir -p "${serve_dir}"

    local master_pdf="${serve_dir}/Slacky_Update_Field_Guide.pdf"
    local tech_pdf="${serve_dir}/Technical_Companion_Guide.pdf"
    local limine_pdf="${serve_dir}/Limine_SecureBoot_Guide.pdf"
    local html_target="${serve_dir}/index.html"

    local master_md
    master_md=$(get_master_field_guide_md_path)
    local tech_md
    tech_md=$(get_technical_companion_guide_md_path)
    local limine_md
    limine_md=$(get_limine_field_guide_md_path)

    log_info "Compiling field guides for mobile delivery..."
    generate_field_guide_pdf "${master_pdf}" "${master_md}" || return 1
    if [ -n "${tech_md}" ] && [ -f "${tech_md}" ]; then
        generate_field_guide_pdf "${tech_pdf}" "${tech_md}" >/dev/null 2>&1 || true
    fi
    if [ -n "${limine_md}" ] && [ -f "${limine_md}" ]; then
        generate_field_guide_pdf "${limine_pdf}" "${limine_md}" >/dev/null 2>&1 || true
    fi
    generate_field_guide_html "${html_target}" "${master_md}" "${limine_md}" "${tech_md}" || return 1

    local port=8765

    # Create standalone multi-threaded HTTP server script
    cat << 'PYSRV_EOF' > "${serve_dir}/server.py"
import os, sys, http.server, socketserver, urllib.parse

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
DIRECTORY = sys.argv[2] if len(sys.argv) > 2 else "/tmp/slacky_guide_transfer"

class GuideHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def do_GET(self):
        if self.path == "/favicon.ico":
            self.send_response(204)
            self.end_headers()
            return
        super().do_GET()

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        parsed = urllib.parse.urlparse(self.path)
        clean_path = parsed.path.lower()
        query = urllib.parse.parse_qs(parsed.query)

        if clean_path.endswith(".pdf"):
            fname = os.path.basename(parsed.path)
            if "inline" in query or query.get("inline", ["0"])[0] == "1":
                self.send_header("Content-Disposition", f'inline; filename="{fname}"')
            else:
                self.send_header("Content-Disposition", f'attachment; filename="{fname}"')
            self.send_header("Content-Type", "application/pdf")
            self.send_header("Cache-Control", "public, max-age=86400")
        elif clean_path.endswith(".html") or clean_path == "/" or clean_path == "":
            self.send_header("Cache-Control", "no-cache, must-revalidate")
            self.send_header("Content-Type", "text/html; charset=utf-8")
        super().end_headers()

    def log_message(self, format, *args):
        pass

class ReusableThreadingServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

if __name__ == "__main__":
    with ReusableThreadingServer(("", PORT), GuideHTTPRequestHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass
PYSRV_EOF

    # Smart Network IP Detection: Prioritizes Wi-Fi interfaces so phones connect seamlessly
    local net_info
    net_info=$(python3 - << 'PYNET'
import subprocess, re

def detect_ips():
    try:
        out = subprocess.check_output(['ip', '-o', '-4', 'addr', 'show'], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        out = ''

    wifi_list = []
    eth_list = []
    other_list = []

    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 4:
            ifname = parts[1]
            ip = parts[3].split('/')[0]
            if ip.startswith('127.'):
                continue
            if re.match(r'^(wl|wlan|wlp|wls|ath|ra|wifi)', ifname, re.I):
                wifi_list.append((ifname, ip))
            elif re.match(r'^(eth|en|em|eno|enp|ens)', ifname, re.I):
                eth_list.append((ifname, ip))
            else:
                other_list.append((ifname, ip))

    primary_ip = ""
    primary_iface = ""
    primary_type = "IP"
    alt_lines = []

    if wifi_list:
        primary_iface, primary_ip = wifi_list[0]
        primary_type = "Wi-Fi"
        for ifn, ip in eth_list:
            alt_lines.append(f"Ethernet ({ifn}): http://{ip}:8765/")
        for ifn, ip in wifi_list[1:]:
            alt_lines.append(f"Wi-Fi ({ifn}): http://{ip}:8765/")
    elif eth_list:
        primary_iface, primary_ip = eth_list[0]
        primary_type = "Ethernet"
        for ifn, ip in eth_list[1:]:
            alt_lines.append(f"Ethernet ({ifn}): http://{ip}:8765/")
    elif other_list:
        primary_iface, primary_ip = other_list[0]
        primary_type = "LAN"
    else:
        try:
            r = subprocess.check_output(['ip', 'route', 'get', '1.1.1.1'], text=True, stderr=subprocess.DEVNULL)
            m = re.search(r'src\s+([^\s]+)', r)
            if m:
                primary_ip = m.group(1)
        except Exception:
            pass
        if not primary_ip:
            primary_ip = "127.0.0.1"

    print(f"{primary_ip}|{primary_iface}|{primary_type}|{';;'.join(alt_lines)}")

detect_ips()
PYNET
)

    local local_ip
    local local_iface
    local local_type
    local alt_nets
    IFS='|' read -r local_ip local_iface local_type alt_nets <<< "${net_info}"

    local_ip="${local_ip:-127.0.0.1}"
    local guide_url="http://${local_ip}:${port}/"

    local server_pid
    python3 "${serve_dir}/server.py" "${port}" "${serve_dir}" >/dev/null 2>&1 &
    server_pid=$!
    sleep 0.3

    if ! kill -0 "${server_pid}" 2>/dev/null; then
        log_error "Failed to start mobile transfer HTTP server on port ${port}."
        rm -rf "${serve_dir}" 2>/dev/null || true
        return 1
    fi

    clear || true
    echo -e "${CYAN}${BOLD}============================================================${RESET}"
    echo -e "${YELLOW}${BOLD}  📲 MOBILE TRANSFER: SLACKY-UPDATE MASTER FIELD GUIDE  ${RESET}"
    echo -e "${CYAN}${BOLD}============================================================${RESET}"
    echo -e "Scan this QR code with your phone camera on your local Wi-Fi network."
    echo -e "${RED}${BOLD}IMPORTANT:${RESET} Tap ${GREEN}${BOLD}[Download PDF]${RESET} on your phone to save the document"
    echo -e "locally before rebooting, so you can read it while in BIOS/UEFI setup!"
    echo ""

    if command -v qrencode >/dev/null 2>&1; then
        qrencode -t ANSIUTF8 "${guide_url}" || qrencode -t UTF8 "${guide_url}"
    else
        echo -e "${YELLOW}[qrencode utility not found]${RESET}"
    fi

    echo ""
    if [ -n "${local_iface}" ]; then
        echo -e "  • ${BOLD}Primary (${local_type} - ${local_iface}):${RESET} ${GREEN}${guide_url}${RESET}"
    else
        echo -e "  • ${BOLD}Direct URL:${RESET}          ${GREEN}${guide_url}${RESET}"
    fi

    if [ -n "${alt_nets}" ]; then
        IFS=';;' read -ra alts <<< "${alt_nets}"
        for alt in "${alts[@]}"; do
            [ -n "${alt}" ] && echo -e "  • ${BOLD}Alternative:${RESET}            ${CYAN}${alt}${RESET}"
        done
    fi
    echo ""
    echo -e "${YELLOW}The local server is active on all interfaces. Keep this open until downloaded on phone.${RESET}"
    echo ""
    read -r -p "Press [ENTER] when finished to stop the server and return..." || true

    kill "${server_pid}" 2>/dev/null || true
    rm -rf "${serve_dir}" 2>/dev/null || true
    log_info "Mobile transfer server stopped."
}

# --- [ INTERACTIVE FIELD GUIDE MENU ] ---
manage_field_guide_interactive() {
    while true; do
        clear || true
        echo -e "${CYAN}${BOLD}============================================================${RESET}"
        echo -e "${YELLOW}${BOLD}⚡ SLACKY-UPDATE MASTER FIELD GUIDE & MOBILE EXPORT ⚡${RESET}"
        echo -e "${CYAN}${BOLD}============================================================${RESET}"
        echo -e "  • ${BOLD}Document:${RESET}    Slackware 15.0 & -current Complete System Manuals"
        echo -e "  • ${BOLD}Language:${RESET}    English (Easy-to-Read Edition)"
        echo -e "  • ${BOLD}Format:${RESET}      Terminal / PDF / HTML / Mobile QR / Email"
        echo ""
        echo -e "  ${BOLD}1.${RESET} Read Master Survival Guide in Terminal"
        echo -e "  ${BOLD}2.${RESET} Read Technical Architecture & Companion Guide in Terminal"
        echo -e "  ${BOLD}3.${RESET} Read Limine & BIOS Playbook in Terminal"
        echo -e "  ${BOLD}4.${RESET} Read Disaster Recovery & Troubleshooting Guide in Terminal"
        echo -e "  ${BOLD}5.${RESET} Export All Guides to PDF (Save to ~/Documents)"
        echo -e "  ${BOLD}6.${RESET} Send Survival Guide via Email (Attach PDF in Mail Client)"
        echo -e "  ${BOLD}7.${RESET} Transfer to Phone via Wi-Fi QR Code (Access in BIOS)"
        echo -e "  ${BOLD}8.${RESET} Return to Previous Menu"
        echo ""
        echo -n "Select operation [1-8]: "
        read -r choice

        case "${choice}" in
            1)
                view_field_guide_terminal "$(get_master_field_guide_md_path)"
                ;;
            2)
                view_field_guide_terminal "$(get_technical_companion_guide_md_path)"
                ;;
            3)
                view_field_guide_terminal "$(get_limine_field_guide_md_path)"
                ;;
            4)
                view_field_guide_terminal "$(get_troubleshooting_guide_md_path)"
                ;;
            5)
                export_field_guide_pdf
                echo ""
                read -r -p "Press [ENTER] to continue..." || true
                ;;
            6)
                send_field_guide_email
                echo ""
                read -r -p "Press [ENTER] to continue..." || true
                ;;
            7)
                transfer_field_guide_qr
                ;;
            8|q|Q)
                return 0
                ;;
            *)
                echo -e "${RED}Invalid selection.${RESET}"
                sleep 1
                ;;
        esac
    done
}
