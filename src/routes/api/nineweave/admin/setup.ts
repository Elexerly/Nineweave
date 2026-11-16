import { createFileRoute } from "@tanstack/react-router";
import { handleAdminRequest } from "@/lib/nineweave/admin-runtime.server";

const handle = ({ request }: { request: Request }) => handleAdminRequest(request);
export const Route = createFileRoute("/api/nineweave/admin/setup")({
  server: { handlers: { GET: handle, POST: handle, OPTIONS: handle, PATCH: handle, DELETE: handle } },
});
