import { Link } from "@tanstack/react-router";

type Block =
  | { type: "h1"; text: string }
  | { type: "h2"; text: string }
  | { type: "p"; text: string }
  | { type: "ul"; items: string[] };

function parseMarkdown(src: string): Block[] {
  const blocks: Block[] = [];
  let list: string[] | null = null;
  const flushList = () => {
    if (list) {
      blocks.push({ type: "ul", items: list });
      list = null;
    }
  };
  for (const raw of src.replace(/\r\n/g, "\n").split("\n")) {
    const line = raw.trimEnd();
    if (!line.trim()) {
      flushList();
      continue;
    }
    if (line.startsWith("## ")) {
      flushList();
      blocks.push({ type: "h2", text: line.slice(3).trim() });
    } else if (line.startsWith("# ")) {
      flushList();
      blocks.push({ type: "h1", text: line.slice(2).trim() });
    } else if (line.startsWith("- ")) {
      if (!list) list = [];
      list.push(line.slice(2).trim());
    } else {
      flushList();
      blocks.push({ type: "p", text: line.trim() });
    }
  }
  flushList();
  return blocks;
}

function inline(text: string) {
  const parts = text.split(/(\*\*[^*]+\*\*)/g);
  return parts.map((part, i) =>
    part.startsWith("**") && part.endsWith("**") ? (
      <strong key={i} className="font-medium text-fg">
        {part.slice(2, -2)}
      </strong>
    ) : (
      <span key={i}>{part}</span>
    ),
  );
}

export function LegalPage({ markdown }: { markdown: string }) {
  const blocks = parseMarkdown(markdown);
  return (
    <main className="flex min-h-dvh flex-col bg-bg text-fg">
      <header className="mx-auto flex w-full max-w-3xl items-center justify-between px-6 py-6">
        <Link to="/" className="font-display text-lg tracking-tight text-fg no-underline">
          Nineweave
        </Link>
        <nav className="flex gap-4 text-sm text-muted">
          <Link to="/terms" className="hover:text-fg">
            Terms
          </Link>
          <Link to="/privacy" className="hover:text-fg">
            Privacy
          </Link>
        </nav>
      </header>
      <article className="mx-auto w-full max-w-3xl flex-1 px-6 pb-16">
        {blocks.map((block, i) => {
          if (block.type === "h1")
            return (
              <h1
                key={i}
                className="font-display mt-4 text-4xl leading-tight tracking-tight sm:text-5xl"
              >
                {block.text}
              </h1>
            );
          if (block.type === "h2")
            return (
              <h2 key={i} className="font-display mt-10 text-2xl tracking-tight">
                {block.text}
              </h2>
            );
          if (block.type === "ul")
            return (
              <ul key={i} className="mt-4 list-disc space-y-2 pl-5 text-base leading-relaxed">
                {block.items.map((item, j) => (
                  <li key={j}>{inline(item)}</li>
                ))}
              </ul>
            );
          const meta = /^\*\*/.test(block.text);
          return (
            <p
              key={i}
              className={
                meta
                  ? "mt-3 text-base leading-relaxed text-fg"
                  : "mt-4 text-base leading-relaxed text-fg"
              }
            >
              {inline(block.text)}
            </p>
          );
        })}
      </article>
      <footer className="mx-auto w-full max-w-3xl px-6 pb-8 text-sm text-muted">
        <div className="flex flex-wrap gap-x-4 gap-y-2 border-t border-line pt-6">
          <Link to="/" className="hover:text-fg">
            Home
          </Link>
          <Link to="/terms" className="hover:text-fg">
            Terms of Service
          </Link>
          <Link to="/privacy" className="hover:text-fg">
            Privacy Policy
          </Link>
        </div>
      </footer>
    </main>
  );
}
