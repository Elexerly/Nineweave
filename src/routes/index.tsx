import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useState } from "react";

export const Route = createFileRoute("/")({ component: Home });

const GREETINGS = [
  "Hello",
  "Hola",
  "Bonjour",
  "Ciao",
  "Hallo",
  "Olá",
  "こんにちは",
  "안녕하세요",
  "مرحبا",
  "Привет",
];

function greetingFor(date: Date) {
  const hour = date.getHours();
  if (hour < 12) return "Good morning";
  if (hour < 17) return "Good afternoon";
  return "Good evening";
}

function Home() {
  const [now, setNow] = useState<Date | null>(null);

  useEffect(() => {
    const tick = () => setNow(new Date());
    tick();
    const id = window.setInterval(tick, 30_000);
    return () => window.clearInterval(id);
  }, []);

  const when = now
    ? now.toLocaleString(undefined, {
        weekday: "long",
        month: "long",
        day: "numeric",
        hour: "numeric",
        minute: "2-digit",
      })
    : null;

  return (
    <main className="flex min-h-dvh flex-col bg-bg text-fg">
      <header className="mx-auto flex w-full max-w-3xl items-center justify-between px-6 py-6">
        <p className="font-display text-lg tracking-tight">Hello World</p>
        <p className="text-sm text-muted">Starter</p>
      </header>

      <section className="mx-auto flex w-full max-w-3xl flex-1 flex-col justify-center px-6 pb-16">
        <p className="rise text-sm font-medium tracking-wide text-primary">
          {now ? greetingFor(now) : "Hello"}
        </p>
        <h1 className="rise font-display mt-4 text-6xl leading-none tracking-tight sm:text-8xl">
          Hello, world.
        </h1>
        <p className="rise mt-6 max-w-md text-lg leading-relaxed text-muted">
          A simple first page, ready to grow. Add a story, a page, or a tool whenever you are.
        </p>
        <p className="mt-8 min-h-6 text-sm text-muted" aria-live="polite">
          {when ? `Local time: ${when}` : "\u00a0"}
        </p>
      </section>

      <footer className="mx-auto w-full max-w-3xl px-6 pb-8">
        <ul className="flex flex-wrap gap-x-4 gap-y-2 border-t border-line pt-6 text-sm text-muted">
          {GREETINGS.map((word) => (
            <li key={word}>{word}</li>
          ))}
        </ul>
      </footer>
    </main>
  );
}
