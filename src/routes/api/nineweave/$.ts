import { createFileRoute } from "@tanstack/react-router";
import { handleNineweave } from "@/lib/nineweave/server";

// Nineweave online API — every /api/nineweave/* path dispatches through one
// handler (see src/lib/nineweave/api.ts and ONLINE_API.md).
const handle = ({ request }: { request: Request }) => handleNineweave(request);

export const Route = createFileRoute("/api/nineweave/$")({
  server: {
    handlers: {
      GET: handle,
      POST: handle,
      PATCH: handle,
      OPTIONS: handle,
    },
  },
});
