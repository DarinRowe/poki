import { useEffect, useState } from "react";
import { api, type AppInfo } from "./api";
import { t, useLang } from "./i18n";
import Setup from "./screens/Setup";
import Phones from "./screens/Phones";
import Account from "./screens/Account";
import Relay from "./screens/Relay";
import Connectors from "./screens/Connectors";
import Debug from "./screens/Debug";
import Settings from "./screens/Settings";
import { listen } from "@tauri-apps/api/event";

type Page = "setup" | "phones" | "account" | "relay" | "connectors" | "debug" | "settings";
const pages: { id: Page; label: string; icon: string }[] = [
  { id: "setup", label: "Set up", icon: "M12 2l8 4.5v11L12 22l-8-4.5v-11L12 2zm0 2.3L6 7.7v8.6l6 3.4 6-3.4V7.7l-6-3.4z" },
  { id: "phones", label: "Phones", icon: "M8 2h8a2 2 0 012 2v16a2 2 0 01-2 2H8a2 2 0 01-2-2V4a2 2 0 012-2zm0 2v16h8V4H8zm3 13h2v2h-2z" },
  { id: "account", label: "Apple ID", icon: "M12 12a4 4 0 100-8 4 4 0 000 8zm0 2c-4 0-8 2-8 5v1h16v-1c0-3-4-5-8-5z" },
  { id: "relay", label: "Relay", icon: "M4 14a4 4 0 014-4h1a5 5 0 019.6 1.2A3.5 3.5 0 0118 18H8a4 4 0 01-4-4z" },
  { id: "connectors", label: "Connectors", icon: "M7 7h4v2H9v6h2v2H7V7zm10 0v10h-4v-2h2V9h-2V7h4zM3 11h4v2H3zm14 0h4v2h-4z" },
  { id: "debug", label: "Debug", icon: "M12 3a5 5 0 015 5v1h2v2h-2v2a5 5 0 01-.5 2.2L19 17l-1.4 1.4-2.2-2.2A5 5 0 0112 18a5 5 0 01-3.4-1.8l-2.2 2.2L5 17l2.5-1.8A5 5 0 017 13v-2H5V9h2V8a5 5 0 015-5z" },
  { id: "settings", label: "Settings", icon: "M12 8a4 4 0 110 8 4 4 0 010-8zm8.9 5.3l-1.9-.4a7 7 0 000-1.8l1.9-.4-.7-2.6-1.8.7a7 7 0 00-1.3-1.3l.7-1.8-2.6-.7-.4 1.9a7 7 0 00-1.8 0l-.4-1.9-2.6.7.7 1.8a7 7 0 00-1.3 1.3l-1.8-.7-.7 2.6 1.9.4a7 7 0 000 1.8l-1.9.4.7 2.6 1.8-.7a7 7 0 001.3 1.3l-.7 1.8 2.6.7.4-1.9a7 7 0 001.8 0l.4 1.9 2.6-.7-.7-1.8a7 7 0 001.3-1.3l1.8.7.7-2.6z" },
];

export default function App() {
  useLang();
  const [page, setPage] = useState<Page>("setup");
  const [info, setInfo] = useState<AppInfo | null>(null);
  useEffect(() => {
    api.appInfo().then((i) => {
      setInfo(i);
      if (i.os === "macos" || i.os === "windows") document.body.classList.add("vibrant");
    });
    const un = listen("renew-requested", () => setPage("phones"));
    return () => { un.then((f) => f()); };
  }, []);
  const win = info?.os !== "macos";
  return (
    <div className="app">
      <div className="drag" />
      <aside className={`sidebar ${win ? "win" : ""}`}>
        <div className="brand"><img src="/icon.png" alt="" /><b>Poki Setup</b></div>
        <nav className="nav">
          {pages.map((p) => (
            <button key={p.id} className={page === p.id ? "on" : ""} onClick={() => setPage(p.id)}>
              <svg viewBox="0 0 24 24" fill="currentColor"><path d={p.icon} /></svg>{t(p.label)}
            </button>
          ))}
        </nav>
        <div className="foot">v{info?.version ?? "…"}</div>
      </aside>
      <main className={`content ${win ? "win" : ""}`}>
        {page === "setup" && <Setup goAccount={() => setPage("account")} />}
        {page === "phones" && <Phones />}
        {page === "account" && <Account info={info} />}
        {page === "relay" && <Relay />}
        {page === "connectors" && <Connectors />}
        {page === "debug" && <Debug />}
        {page === "settings" && <Settings info={info} />}
      </main>
    </div>
  );
}
