import { useEffect, useState } from "react";
import { api, failureText, type Connector } from "../api";
import { t } from "../i18n";
import { Capsule, Card, Copy, ErrorBox, Field, Pill } from "../ui";

export default function Connectors() {
  const [list, setList] = useState<Connector[]>([]);
  const [name, setName] = useState("");
  const [url, setUrl] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [checking, setChecking] = useState<string | null>(null);
  const [open, setOpen] = useState<string | null>(null);
  const [snips, setSnips] = useState<[string, string][]>([]);
  const load = () => api.connectors().then(setList);
  useEffect(() => { load(); }, []);
  const redact = (u: string) => u.replace(/\/v1\/([a-z2-7]{8})[a-z2-7]+\/[^/]+\//, "/v1/$1…/••••••/");
  return (
    <>
      <h1 className="page-title">{t("Connectors")}</h1>
      <p className="page-sub">Connector links are made and revoked in Poki on the iPhone (Connect → Add connector); the secret never leaves the phone. Keep them here to check them end to end and to copy client setups.</p>
      <ErrorBox error={error} />
      <Card>
        <form className="row" style={{ alignItems: "flex-end" }} onSubmit={async (e) => { e.preventDefault(); setError(null); try { await api.connectorAdd(name, url); setName(""); setUrl(""); load(); } catch (err) { setError(failureText(err)); } }}>
          <Field label={t("Name")}><input className="input" style={{ width: 160 }} value={name} onChange={(e) => setName(e.target.value)} placeholder="Claude" /></Field>
          <div className="grow"><Field label={t("Connector link")}><input className="input mono" value={url} onChange={(e) => setUrl(e.target.value)} placeholder="https://poki-relay.….workers.dev/v1/…/…/mcp" /></Field></div>
          <Capsule type="submit" disabled={!name || !url}>{t("Add")}</Capsule>
        </form>
      </Card>
      {list.map((c) => (
        <Card key={c.url}>
          <div className="row between" style={{ alignItems: "flex-start" }}>
            <div className="grow"><h2 style={{ margin: 0 }}>{c.name}</h2><code className="small break">{redact(c.url)}</code>{c.last_check && <div className="muted small">{c.last_check.detail}</div>}</div>
            {c.last_check && <Pill tone={c.last_check.ok ? "ok" : c.last_check.relay_ok ? "warn" : "bad"}>{c.last_check.ok ? "OK" : c.last_check.phone_online ? "phone" : c.last_check.relay_ok ? "offline" : "relay"}</Pill>}
          </div>
          <div className="row" style={{ marginTop: 10 }}>
            <Copy text={c.url} />
            <Capsule kind="ghost" sm disabled={checking !== null} onClick={async () => { setChecking(c.url); try { await api.connectorCheck(c.url); } catch (e) { setError(failureText(e)); } setChecking(null); load(); }}>{checking === c.url ? "…" : t("Check")}</Capsule>
            <Capsule kind="ghost" sm onClick={async () => { if (open === c.url) { setOpen(null); return; } setSnips(await api.connectorSnippets(c.url)); setOpen(c.url); }}>{t("Snippets")}</Capsule>
            <Capsule kind="danger" sm onClick={() => api.connectorForget(c.url).then(load)}>{t("Forget")}</Capsule>
          </div>
          {open === c.url && snips.map(([title, body]) => (
            <div key={title} style={{ marginTop: 12 }}>
              <div className="row between"><b>{title}</b><Copy text={body} /></div>
              <pre className="snippet">{body}</pre>
            </div>
          ))}
        </Card>
      ))}
    </>
  );
}
