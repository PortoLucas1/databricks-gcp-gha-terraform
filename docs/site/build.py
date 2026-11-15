"""Builds the lab's published pages from the repository's markdown:

  index.html          the deliverables, E1-E7 (docs/deliverables/*.md)
  status.html         the Entra test status (status.md, in this folder)
  aim-assessment.html the AIM assessment (docs/AIM_ENTRA_ASSESSMENT.md)

Run from anywhere: python docs/site/build.py. The pages are standalone HTML:
open them locally, or serve the folder (for example with GitHub Pages).

Markdown subset: headings, paragraphs, tables, nested lists, fenced code,
inline code/bold/italic/strike/links. Mermaid blocks are replaced by the
hand-drawn SVG figures below.
"""
import html, pathlib, re, sys

REPO = pathlib.Path(__file__).resolve().parents[2]
DOCS = REPO / "docs" / "deliverables"
SITE = pathlib.Path(__file__).resolve().parent

SECTIONS = [  # (anchor, file)
    ("recommendation", "E4_RECOMMENDATION.md"),
    ("guide", "E6_CONFIGURATION_GUIDE.md"),
    ("identity", "E3_IDENTITY.md"),
    ("results", "E1_RESULTS.md"),
    ("capabilities", "E2_CAPABILITIES.md"),
    ("teardown", "E7_TEARDOWN.md"),
]
ANCHOR = {f: a for a, f in SECTIONS}

# ----------------------------------------------------------------- inline
def inline(text):
    codes = []
    def keep(m):
        codes.append("<code>" + html.escape(m.group(1)) + "</code>")
        return f"\x00{len(codes)-1}\x00"
    text = re.sub(r"`([^`]+)`", keep, text)
    links = []
    def link(m):
        label, url = html.escape(m.group(1), quote=False), m.group(2)
        name = url.rstrip("/").split("/")[-1].split("#")[0]
        if url.startswith("http"):
            links.append(f'<a href="{html.escape(url)}" target="_blank" rel="noopener">{label}</a>')
        elif name in ANCHOR:
            links.append(f'<a href="#{ANCHOR[name]}">{label}</a>')
        else:  # files in the private repository: keep the name, drop the link
            links.append(label)
        return f"\x01{len(links)-1}\x01"
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, text)
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", text)
    text = re.sub(r"~~(.+?)~~", r"<s>\1</s>", text)
    text = re.sub(r"\x01(\d+)\x01", lambda m: links[int(m.group(1))], text)
    text = re.sub(r"\x00(\d+)\x00", lambda m: codes[int(m.group(1))], text)
    return text

# ----------------------------------------------------------------- blocks
LIST_RE = re.compile(r"^(\s*)([-*]|\d+\.)\s+(.*)$")

def indent_of(line):
    return len(line) - len(line.lstrip(" "))

def table(rows):
    def cells(r):
        r = r.strip()
        if r.startswith("|"): r = r[1:]
        if r.endswith("|"): r = r[:-1]
        return [c.strip() for c in re.split(r"(?<!\\)\|", r)]
    head = cells(rows[0])
    body = [cells(r) for r in rows[2:]]
    out = ['<div class="tbl"><table><thead><tr>']
    out += [f"<th>{inline(c)}</th>" for c in head]
    out.append("</tr></thead><tbody>")
    for r in body:
        out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>")
    out.append("</tbody></table></div>")
    return "".join(out)

def blocks(lines, figures):
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1; continue
        if line.lstrip().startswith("```"):
            lang = line.strip()[3:].strip()
            j = i + 1
            while not lines[j].lstrip().startswith("```"): j += 1
            body = "\n".join(l[indent_of(line):] for l in lines[i+1:j])
            if lang == "mermaid":
                out.append(figures.pop(0))
            else:
                out.append(f'<pre class="code"><code>{html.escape(body)}</code></pre>')
            i = j + 1; continue
        m = re.match(r"^(#{1,4})\s+(.*)$", line)
        if m:
            lvl = len(m.group(1)); txt = m.group(2)
            out.append(f"<h{lvl+1}>{inline(txt)}</h{lvl+1}>")
            i += 1; continue
        if line.lstrip().startswith("|"):
            j = i
            while j < len(lines) and lines[j].lstrip().startswith("|"): j += 1
            out.append(table(lines[i:j])); i = j; continue
        lm = LIST_RE.match(line)
        if lm:
            base = indent_of(line)
            ordered = lm.group(2)[0].isdigit()
            items, cur = [], None
            j = i
            while j < len(lines):
                l = lines[j]
                mm = LIST_RE.match(l)
                if mm and indent_of(l) == base:
                    cur = [mm.group(3)]; items.append((mm.group(2), cur)); j += 1; continue
                if not l.strip():
                    # blank: continue only if the next non-blank line is indented
                    k = j
                    while k < len(lines) and not lines[k].strip(): k += 1
                    if k < len(lines) and indent_of(lines[k]) > base:
                        cur.append(""); j += 1; continue
                    break
                if indent_of(l) > base:
                    cur.append(l); j += 1; continue
                break
            tag = "ol" if ordered else "ul"
            out.append(f"<{tag}>")
            for marker, content in items:
                first, rest = content[0], content[1:]
                if rest:
                    ind = min(indent_of(l) for l in rest if l.strip())
                    rest = [l[ind:] for l in rest]
                    out.append(f"<li>{blocks([first] + rest, figures)}</li>")
                else:
                    out.append(f"<li>{inline(first)}</li>")
            out.append(f"</{tag}>")
            i = j; continue
        j = i
        para = []
        while j < len(lines) and lines[j].strip() and not lines[j].lstrip().startswith(("|", "```", "#")) and not LIST_RE.match(lines[j]):
            para.append(lines[j].strip()); j += 1
        out.append(f"<p>{inline(' '.join(para))}</p>")
        i = j
    return "".join(out)

# ----------------------------------------------------------------- figures
def svg_text(x, y, s, cls="t", anchor="middle", size=None):
    sz = f' font-size="{size}"' if size else ""
    return f'<text x="{x}" y="{y}" class="{cls}" text-anchor="{anchor}"{sz}>{html.escape(s)}</text>'

def node(x, y, w, h, title, sub=None, kind="n"):
    s = f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" class="node {kind}"/>'
    cy = y + h / 2 + (4 if not sub else -3)
    s += svg_text(x + w / 2, cy, title, "t strong")
    if sub:
        s += svg_text(x + w / 2, cy + 15, sub, "t small muted")
    return s

def box(x, y, w, h, label, kind="zone"):
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" class="{kind}"/>'
            + svg_text(x + 12, y + 20, label.upper(), "t label", "start"))

def arrow(points, cls="flow", marker="arr"):
    pts = " ".join(f"{x},{y}" for x, y in points)
    return f'<polyline points="{pts}" class="{cls}" marker-end="url(#{marker})"/>'

def architecture():
    W, H = 1040, 640
    s = [f'<svg viewBox="0 0 {W} {H}" role="img" aria-label="Architecture: GitHub-hosted runners build the GCP project and call the Databricks Accounts API with two tokens; a self-hosted runner in the users\' VPC reaches the workspace through the front-end endpoint; cluster nodes reach the control plane and relay only through back-end endpoints; the internet is refused.">']
    s.append('<defs>'
             '<marker id="arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" class="ah"/></marker>'
             '<marker id="arr-g" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" class="ah-g"/></marker>'
             '<marker id="arr-d" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" class="ah-d"/></marker>'
             '<marker id="arr-x" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" class="ah-x"/></marker>'
             '</defs>')
    # columns
    s.append(box(16, 40, 200, 568, "GitHub"))
    s.append(box(244, 40, 500, 568, "Google Cloud", "zone g"))
    s.append(box(772, 40, 252, 568, "Databricks control plane", "zone d"))
    # GitHub
    s.append(node(36, 84, 160, 60, "GitHub-hosted runner", "GCP + account stacks"))
    s.append(node(36, 178, 160, 52, "OIDC issuer", "signs a token per job"))
    s.append(node(36, 476, 160, 56, "Any internet client", "even a workspace admin", "n x"))
    # CI project
    s.append(box(264, 70, 460, 112, "CI project (bootstrap/)", "sub g"))
    s.append(node(280, 104, 136, 58, "Identity pool", "provider github-oidc", "n g"))
    s.append(node(428, 104, 136, 58, "Apply · plan", "service accounts", "n g"))
    s.append(node(576, 104, 132, 58, "State bucket", "one prefix per stack", "n g"))
    # Workspace project
    s.append(box(264, 200, 460, 366, "Workspace project", "sub g"))
    s.append(box(280, 228, 428, 132, "Users' VPC", "sub2"))
    s.append(node(296, 262, 124, 56, "Response policy", "workspace names only", "n g"))
    s.append(node(436, 262, 120, 56, "Self-hosted runner", "workspace stack", "n"))
    s.append(node(572, 262, 120, 56, "Front-end endpoint", "PSC", "n g"))
    s.append(svg_text(296, 345, "Cloud NAT: egress for the runner only", "t small muted", "start"))
    s.append(box(280, 376, 428, 176, "Workspace VPC · compute plane", "sub2"))
    s.append(node(296, 410, 132, 58, "Cluster nodes", "no external IP, no NAT", "n"))
    s.append(node(296, 484, 132, 52, "Private zone", "gcp.databricks.com", "n g"))
    s.append(node(492, 404, 140, 46, "Back-end REST", "PSC endpoint", "n g"))
    s.append(node(492, 474, 140, 46, "Back-end relay", "PSC endpoint", "n g"))
    # Databricks
    s.append(node(792, 84, 212, 60, "Accounts API", "accounts.gcp.databricks.com", "n d"))
    s.append(node(792, 260, 212, 60, "Workspace", "web app + REST · public access off", "n d"))
    s.append(node(792, 474, 212, 46, "Secure cluster relay", "", "n d"))
    # flows
    s.append(arrow([(196, 96), (230, 96), (230, 24), (990, 24), (990, 84)], "flow d", "arr-d"))
    s.append(svg_text(600, 17, "Accounts API: Databricks token + Google token in X-Databricks-GCP-SA-Access-Token", "t small dtext"))
    s.append(arrow([(196, 130), (280, 130)], "flow g", "arr-g"))
    s.append(svg_text(238, 124, "STS", "t small gtext"))
    s.append(arrow([(116, 178), (116, 144)], "flow"))
    s.append(svg_text(122, 166, "JWT", "t small muted", "start"))
    s.append(arrow([(556, 290), (572, 290)], "flow"))
    s.append(arrow([(436, 290), (420, 290)], "flow dash"))
    s.append(arrow([(692, 290), (792, 290)], "flow d", "arr-d"))
    s.append(svg_text(742, 282, "private", "t small dtext"))
    s.append(arrow([(428, 428), (492, 427)], "flow"))
    s.append(arrow([(428, 452), (492, 497)], "flow"))
    s.append(arrow([(362, 484), (362, 468)], "flow dash"))
    s.append(arrow([(632, 420), (700, 420), (760, 320), (792, 310)], "flow d", "arr-d"))
    s.append(arrow([(632, 497), (792, 497)], "flow d", "arr-d"))
    # refusal
    s.append(arrow([(116, 532), (116, 586), (1012, 586), (1012, 300), (1004, 300)], "flow x", "arr-x"))
    s.append(svg_text(560, 580, "from the internet: 403 Unauthorized network access to workspace", "t small xtext"))
    s.append('</svg>')
    return "".join(s)

def auth_flow():
    cols = [("GitHub Actions job", ""), ("GitHub OIDC", "issuer"), ("Google STS", "token exchange"),
            ("IAM Credentials", "service accounts"), ("Databricks", "token endpoint"), ("Accounts API", "or workspace API")]
    X = [90, 250, 410, 570, 730, 890]
    kinds = ["n", "n", "n g", "n g", "n d", "n d"]
    msgs = [  # (from, to, label, check, reply)
        (0, 1, "token, audience = pool provider", None, False),
        (1, 0, "signed JWT: sub, repository_owner_id, repository, ref", None, True),
        (0, 2, "exchange the JWT", "checks issuer + condition: owner ID and repository", False),
        (2, 0, "federated token", None, True),
        (0, 3, "access token for the apply identity", "checks workloadIdentityUser: refs/heads/main", False),
        (3, 0, "Google access token, 1 hour", None, True),
        (0, 1, "token, audience = Databricks account ID", None, False),
        (1, 0, "signed JWT", None, True),
        (0, 4, "token exchange, client_id = principal", "checks federation policy: issuer, exact sub, audience", False),
        (4, 0, "Databricks token, 1 hour", None, True),
        (0, 5, "POST /workspaces + X-Databricks-GCP-SA-Access-Token", "Databricks acts in the project with the Google token", False),
    ]
    ys, y = [], 112
    for m in msgs:
        ys.append(y); y += 58 if m[3] else 36
    H = y + 30
    W = 990
    s = [f'<svg viewBox="0 0 {W} {H}" role="img" aria-label="Authentication sequence: the job gets a GitHub OIDC token, exchanges it at Google STS and IAM Credentials for the apply identity\'s access token, gets a second GitHub token for the Databricks account and exchanges it for a Databricks token, then calls the Accounts API with both tokens.">']
    s.append('<defs>'
             '<marker id="sa" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" class="ah"/></marker>'
             '</defs>')
    # phase bands
    phases = [(0, 5, "google-github-actions/auth"), (6, 9, "Databricks provider, github-oidc"), (10, 10, "REST provider")]
    for a, b, label in phases:
        y0, y1 = ys[a] - 18, ys[b] + (40 if msgs[b][3] else 14)
        s.append(f'<rect x="8" y="{y0}" width="{W-16}" height="{y1-y0}" rx="6" class="band"/>')
        s.append(svg_text(W - 18, y0 + 14, label, "t label", "end"))
    for (name, sub), x, k in zip(cols, X, kinds):
        s.append(f'<line x1="{x}" y1="76" x2="{x}" y2="{H-14}" class="life"/>')
        s.append(node(x - 72, 24, 144, 50, name, sub or None, k))
    for idx, ((a, b, label, check, reply), y) in enumerate(zip(msgs, ys)):
        x1, x2 = X[a], X[b]
        d = 6 if x2 > x1 else -6
        cls = "flow reply" if reply else "flow"
        s.append(f'<line x1="{x1}" y1="{y}" x2="{x2 - d}" y2="{y}" class="{cls}" marker-end="url(#sa)"/>')
        mid = (x1 + x2) / 2
        s.append(svg_text(mid, y - 6, f"{idx+1}  {label}", "t small"))
        if check:
            tw = 7.0 * len(check) + 18
            cx = min(max(X[b], tw / 2 + 30), W - tw / 2 - 10)
            kind = "g" if b in (2, 3) else "d"
            s.append(f'<rect x="{cx - tw/2}" y="{y + 9}" width="{tw}" height="22" rx="11" class="tag {kind}"/>')
            s.append(svg_text(cx, y + 24, check, f"t small {kind}text"))
    s.append('</svg>')
    return "".join(s)

FIG_ARCH = ('<figure class="fig" id="architecture"><div class="scroll">' + architecture() + '</div>'
            '<figcaption><strong>Architecture.</strong> GitHub-hosted runners build the GCP project and call the Databricks Accounts API with two short-lived tokens. '
            'Workspace-level Terraform runs on a self-hosted runner inside the users\' network and reaches the workspace only through the front-end endpoint. '
            'Cluster nodes have no internet route: they reach the control plane and the relay through back-end endpoints. From the internet, the workspace refuses even its own admins.</figcaption></figure>')
FIG_AUTH = ('<figure class="fig" id="auth-flow"><div class="scroll">' + auth_flow() + '</div>'
            '<figcaption><strong>Authentication.</strong> No key or stored secret anywhere. Each job asks GitHub for a signed token and trades it twice: at Google for the apply identity\'s access token, and at Databricks for the automation principal\'s token. '
            'Every check in a pill is configured once, by administrators, in <code>bootstrap/</code>.</figcaption></figure>')

# ----------------------------------------------------------------- page
def section(anchor, fn):
    lines = (DOCS / fn).read_text(encoding="utf-8").splitlines()
    figs = []
    if fn.startswith("E6"): figs = [FIG_ARCH]
    if fn.startswith("E3"): figs = [FIG_AUTH]
    title = lines[0].lstrip("# ").strip()
    m = re.match(r"(E\d)\.\s*(.*)", title)
    code, name = (m.group(1), m.group(2)) if m else ("", title)
    body = blocks(lines[1:], figs)
    assert not figs, f"figure not placed in {fn}"
    return (f'<section id="{anchor}" class="doc"><header class="doc-head"><span class="code-tag">{code}</span>'
            f'<h2>{inline(name)}</h2></header>{body}</section>'), code, name

def standalone(page, mermaid=False):
    """Wrap a page body in a document (a published Artifact adds this itself)."""
    extra = ""
    if mermaid:
        extra = ('<script src="https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js"></script>\n'
                 '<script>mermaid.initialize({ startOnLoad: true, theme: '
                 'window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "default" });</script>\n')
    return ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
            '</head>\n<body style="margin:0">\n' + page + "\n" + extra + "</body>\n</html>\n")


def page_style():
    tpl = (SITE / "template.html").read_text(encoding="utf-8")
    return tpl[tpl.index('<link rel="preconnect"'):tpl.index("</style>") + len("</style>")]


def single(title_tag, eyebrow, md_lines, figures=()):
    body = blocks(md_lines[1:], list(figures))
    return (f"<title>{title_tag}</title>\n{page_style()}\n"
            "<style>.single { max-width: 960px; margin: 0 auto; }\n"
            "pre.mermaid { background: none; border: 0; margin: 0; min-width: 720px; text-align: center; }</style>\n"
            f'<header class="mast single">\n  <div class="eyebrow">{eyebrow}</div>\n'
            f"  <h1>{inline(md_lines[0].lstrip('# ').strip())}</h1>\n</header>\n"
            f'<main class="single"><section class="doc">{body}</section></main>\n')


def main():
    # Deliverables
    parts, toc = [], []
    for a, f in SECTIONS:
        h, code, name = section(a, f)
        parts.append(h)
        toc.append(f'<li><a href="#{a}"><span>{code}</span>{html.escape(name.split(":")[0])}</a></li>')
    tpl = (SITE / "template.html").read_text(encoding="utf-8")
    page = tpl.replace("{{TOC}}", "".join(toc)).replace("{{SECTIONS}}", "".join(parts))
    (SITE / "index.html").write_text(standalone(page), encoding="utf-8", newline="\n")

    # Status
    md = (SITE / "status.md").read_text(encoding="utf-8").splitlines()
    eyebrow = ("<span>Test status</span><span>Databricks on Google Cloud · GitHub Actions · Microsoft Entra ID</span>"
               "<span><b>Complete, 2026-11-14</b></span>")
    (SITE / "status.html").write_text(standalone(single("Entra GHA Test Status", eyebrow, md)), encoding="utf-8", newline="\n")

    # AIM assessment
    md = (REPO / "docs" / "AIM_ENTRA_ASSESSMENT.md").read_text(encoding="utf-8").splitlines()
    mer = re.search(r"```mermaid\n(.*?)```", "\n".join(md), re.S).group(1)
    fig = ('<figure class="fig"><div class="scroll"><pre class="mermaid">' + html.escape(mer) + "</pre></div>"
           "<figcaption><strong>Three ways to wire it.</strong> The Google side, which supplies the token for the header, "
           "is the same in all three.</figcaption></figure>")
    eyebrow = ("<span>Assessment</span><span>Databricks on Google Cloud · GitHub Actions · Microsoft Entra ID</span>"
               "<span><b>2026-11-13; open points tested the same day</b></span>")
    page = single("Entra AIM Pipeline Identity", eyebrow, md, [fig]).replace('href="#results"', 'href="index.html#results"')
    (SITE / "aim-assessment.html").write_text(standalone(page, mermaid=True), encoding="utf-8", newline="\n")
    for n in ("index.html", "status.html", "aim-assessment.html"):
        print(n, (SITE / n).stat().st_size)


main()
