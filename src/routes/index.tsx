import { createFileRoute } from "@tanstack/react-router";
import gameHtml from "../../public/index.html?raw";

/**
 * The Godot web export is the site homepage. Static assets (index.js / .wasm /
 * .pck / worklets / icons) live in public/ and are served by the CDN. This
 * route returns the game's own HTML document so / is not the Hello World shell
 * and so /terms, /privacy, and /api/nineweave stay on their own routes.
 */
const gamePage = () =>
  new Response(gameHtml, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-cache",
    },
  });

export const Route = createFileRoute("/")({
  server: {
    handlers: {
      GET: gamePage,
    },
  },
});
