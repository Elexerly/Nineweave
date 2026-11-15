import { createFileRoute } from "@tanstack/react-router";
import { LegalPage } from "@/components/legal-page";
import markdown from "../../legal/privacy.md?raw";

export const Route = createFileRoute("/privacy")({
  head: () => ({
    meta: [
      { title: "Privacy Policy — Nineweave" },
      {
        name: "description",
        content: "Privacy Policy for Nineweave, the Ultimate Tic Tac Toe game.",
      },
    ],
  }),
  component: PrivacyPage,
});

function PrivacyPage() {
  return <LegalPage markdown={markdown} />;
}
