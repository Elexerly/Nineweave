import { createFileRoute } from "@tanstack/react-router";
import { adminSetupPage } from "@/lib/nineweave/admin-page";
import html from "../../lib/nineweave/admin-setup.html?raw";

export const Route = createFileRoute("/admin/setup")({
  server: { handlers: { GET: () => adminSetupPage(html) } },
});
